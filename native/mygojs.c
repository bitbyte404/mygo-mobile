// mygojs: a tiny C bridge between Dart (dart:ffi) and QuickJS-ng.
//
// Everything crosses as JSON text plus an optional byte buffer:
//   JS -> Dart: the global __mg_send(op, json, bytes?) calls the Dart callback
//               synchronously and returns its JSON answer (parsed by JS).
//   Dart -> JS: mg_call_global(eng, fn, json, bytes) calls a global JS
//               function with (json, ArrayBuffer?) and then runs pending jobs.
// Async work (fetch, timers) is built on top in JS: __mg_send returns at once,
// and Dart later settles it through mg_call_global("__mg_settle", ...).
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "quickjs.h"

#if defined(_WIN32)
#define MG_EXPORT __declspec(dllexport)
#else
#define MG_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

// The Dart callback. Answer is malloc'd UTF-8 JSON (Dart allocates it with
// malloc; we free it), or NULL for undefined. *err is set non-zero when the
// answer is an error message to throw.
typedef char *(*mg_send_cb)(int64_t engine, const char *op, const char *json,
                            const uint8_t *bytes, int64_t nbytes, int32_t *err);

typedef struct {
  JSRuntime *rt;
  JSContext *ctx;
  int64_t id;
  mg_send_cb send;
  int64_t deadline_ms; // 0 = none
  JSValue ns;          // module namespace
  int has_ns;
  int depth;           // nested mg_* entries on this engine (a host callback re-entering)
} mg_engine;

// QuickJS checks for stack overflow against the stack pointer it saw when the
// runtime was made (JS_NewRuntime) or last told (JS_UpdateStackTop). A Dart
// isolate is not bound to one OS thread: between calls it can resume on another
// thread of the pool, whose stack lies elsewhere, so the saved top is
// meaningless there and an ordinary call may fail with "Maximum call stack size
// exceeded" (or the check may not fire at all). So every entry point re-reads
// the stack top on the thread it runs on. Only the outermost entry does: a host
// callback (__mg_send) re-entering on the same thread must keep the outer top,
// or the limit would move down the stack with each nesting.
#define MG_ENTER(e) do { if ((e)->depth++ == 0) JS_UpdateStackTop((e)->rt); } while (0)
#define MG_LEAVE(e) do { (e)->depth--; } while (0)

static int64_t now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static int interrupt_handler(JSContext *ctx, void *opaque) {
  mg_engine *e = (mg_engine *)opaque;
  return e->deadline_ms && now_ms() > e->deadline_ms;
}

static JSValue js_mg_send(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
  mg_engine *e = (mg_engine *)JS_GetContextOpaque(ctx);
  const char *op = JS_ToCString(ctx, argc > 0 ? argv[0] : JS_UNDEFINED);
  const char *json = argc > 1 && !JS_IsUndefined(argv[1]) ? JS_ToCString(ctx, argv[1]) : NULL;
  if (!op) return JS_EXCEPTION;
  uint8_t *bytes = NULL;
  size_t nbytes = 0;
  if (argc > 2 && !JS_IsUndefined(argv[2]) && !JS_IsNull(argv[2])) {
    bytes = JS_GetUint8Array(ctx, &nbytes, argv[2]);
    if (!bytes) {
      JS_FreeValue(ctx, JS_GetException(ctx));
      bytes = JS_GetArrayBuffer(ctx, &nbytes, argv[2]);
      if (!bytes) JS_FreeValue(ctx, JS_GetException(ctx));
    }
  }
  int32_t err = 0;
  // Dart may take a while (it never blocks on the network here), so don't
  // count this time against the deadline.
  int64_t saved = e->deadline_ms;
  e->deadline_ms = 0;
  char *answer = e->send(e->id, op, json ? json : "", bytes, (int64_t)nbytes, &err);
  e->deadline_ms = saved;
  JS_FreeCString(ctx, op);
  if (json) JS_FreeCString(ctx, json);
  if (err) {
    JSValue ex = JS_NewError(ctx);
    JS_DefinePropertyValueStr(ctx, ex, "message", JS_NewString(ctx, answer ? answer : "host error"),
                              JS_PROP_WRITABLE | JS_PROP_CONFIGURABLE);
    free(answer);
    return JS_Throw(ctx, ex);
  }
  if (!answer) return JS_UNDEFINED;
  JSValue v = JS_NewString(ctx, answer);
  free(answer);
  return v;
}

// Returns the error text of the pending exception, malloc'd.
static char *take_exception(JSContext *ctx) {
  JSValue ex = JS_GetException(ctx);
  const char *msg = JS_ToCString(ctx, ex);
  char *out = NULL;
  JSValue stack = JS_UNDEFINED;
  if (JS_IsObject(ex)) stack = JS_GetPropertyStr(ctx, ex, "stack");
  const char *st = JS_IsString(stack) ? JS_ToCString(ctx, stack) : NULL;
  size_t n = (msg ? strlen(msg) : 7) + (st ? strlen(st) + 1 : 0) + 1;
  out = (char *)malloc(n);
  snprintf(out, n, "%s%s%s", msg ? msg : "unknown", st ? "\n" : "", st ? st : "");
  if (msg) JS_FreeCString(ctx, msg);
  if (st) JS_FreeCString(ctx, st);
  JS_FreeValue(ctx, stack);
  JS_FreeValue(ctx, ex);
  return out;
}

MG_EXPORT void *mg_new(int64_t id, mg_send_cb send, int64_t memory_limit) {
  mg_engine *e = (mg_engine *)calloc(1, sizeof(mg_engine));
  e->id = id;
  e->send = send;
  e->rt = JS_NewRuntime(); // takes this thread's stack top
  if (memory_limit > 0) JS_SetMemoryLimit(e->rt, (size_t)memory_limit);
  // 1 MiB, QuickJS's own default: within any thread stack the Dart VM gives an
  // isolate's pool threads, so an overflow throws in JS rather than faulting.
  JS_SetMaxStackSize(e->rt, 1024 * 1024);
  JS_SetInterruptHandler(e->rt, interrupt_handler, e);
  e->ctx = JS_NewContext(e->rt);
  JS_SetContextOpaque(e->ctx, e);
  JSValue global = JS_GetGlobalObject(e->ctx);
  JS_SetPropertyStr(e->ctx, global, "__mg_send", JS_NewCFunction(e->ctx, js_mg_send, "__mg_send", 3));
  JS_FreeValue(e->ctx, global);
  return e;
}

MG_EXPORT void mg_free(void *p) {
  mg_engine *e = (mg_engine *)p;
  if (!e) return;
  JS_UpdateStackTop(e->rt);
  if (e->has_ns) JS_FreeValue(e->ctx, e->ns);
  JS_FreeContext(e->ctx);
  JS_FreeRuntime(e->rt);
  free(e);
}

MG_EXPORT void mg_free_string(char *s) { free(s); }

MG_EXPORT void mg_set_deadline(void *p, int64_t ms_from_now) {
  mg_engine *e = (mg_engine *)p;
  e->deadline_ms = ms_from_now > 0 ? now_ms() + ms_from_now : 0;
}

// Runs every pending job. Returns NULL, or a malloc'd error of the last job
// that threw (a job's own unhandled error doesn't stop the others).
static char *mg_run_jobs_impl(void *p) {
  mg_engine *e = (mg_engine *)p;
  char *err = NULL;
  for (;;) {
    JSContext *c;
    int r = JS_ExecutePendingJob(e->rt, &c);
    if (r == 0) break;
    if (r < 0) {
      free(err);
      err = take_exception(c);
    }
  }
  return err;
}

// Evaluates a classic script. Returns NULL or a malloc'd error.
static char *mg_eval_script_impl(void *p, const char *name, const char *src) {
  mg_engine *e = (mg_engine *)p;
  JSValue v = JS_Eval(e->ctx, src, strlen(src), name, JS_EVAL_TYPE_GLOBAL);
  if (JS_IsException(v)) return take_exception(e->ctx);
  JS_FreeValue(e->ctx, v);
  return mg_run_jobs_impl(p);
}

// Evaluates the plugin's ES module and keeps its namespace as the global
// __mg_exports. Returns NULL or a malloc'd error.
static char *mg_eval_module_impl(void *p, const char *name, const char *src) {
  mg_engine *e = (mg_engine *)p;
  JSContext *ctx = e->ctx;
  JSValue fn = JS_Eval(ctx, src, strlen(src), name, JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY);
  if (JS_IsException(fn)) return take_exception(ctx);
  JSModuleDef *m = (JSModuleDef *)JS_VALUE_GET_PTR(fn);
  JSValue res = JS_EvalFunction(ctx, fn); // frees fn
  if (JS_IsException(res)) return take_exception(ctx);
  char *err = mg_run_jobs_impl(p);
  // A module's evaluation answers a promise (top-level await); a rejected one is an error.
  if (JS_IsObject(res) && JS_PromiseState(ctx, res) == JS_PROMISE_REJECTED) {
    JSValue reason = JS_PromiseResult(ctx, res);
    JS_Throw(ctx, reason);
    free(err);
    err = take_exception(ctx);
  }
  JS_FreeValue(ctx, res);
  if (err) return err;
  e->ns = JS_GetModuleNamespace(ctx, m);
  e->has_ns = 1;
  JSValue global = JS_GetGlobalObject(ctx);
  JS_SetPropertyStr(ctx, global, "__mg_exports", JS_DupValue(ctx, e->ns));
  JS_FreeValue(ctx, global);
  return NULL;
}

// Calls the global function `fn` with (json-string, ArrayBuffer|undefined),
// then runs pending jobs. Returns NULL, or a malloc'd error.
static char *mg_call_global_impl(void *p, const char *fn, const char *json, const uint8_t *bytes,
                               int64_t nbytes) {
  mg_engine *e = (mg_engine *)p;
  JSContext *ctx = e->ctx;
  JSValue global = JS_GetGlobalObject(ctx);
  JSValue f = JS_GetPropertyStr(ctx, global, fn);
  JS_FreeValue(ctx, global);
  if (!JS_IsFunction(ctx, f)) {
    JS_FreeValue(ctx, f);
    char *m = (char *)malloc(64 + strlen(fn));
    sprintf(m, "%s is not a function", fn);
    return m;
  }
  JSValue args[2];
  args[0] = JS_NewString(ctx, json ? json : "");
  args[1] = bytes ? JS_NewArrayBufferCopy(ctx, bytes, (size_t)nbytes) : JS_UNDEFINED;
  JSValue r = JS_Call(ctx, f, JS_UNDEFINED, 2, args);
  JS_FreeValue(ctx, args[0]);
  JS_FreeValue(ctx, args[1]);
  JS_FreeValue(ctx, f);
  char *err = NULL;
  if (JS_IsException(r))
    err = take_exception(ctx);
  else
    JS_FreeValue(ctx, r);
  char *jerr = mg_run_jobs_impl(p);
  if (err) {
    free(jerr);
    return err;
  }
  return jerr;
}

// The names the module exports, as a malloc'd JSON array.
static char *mg_export_names_impl(void *p) {
  mg_engine *e = (mg_engine *)p;
  const char *src = "JSON.stringify(Object.keys(globalThis.__mg_exports || {}))";
  JSValue v = JS_Eval(e->ctx, src, strlen(src), "<names>", JS_EVAL_TYPE_GLOBAL);
  if (JS_IsException(v)) return take_exception(e->ctx);
  const char *s = JS_ToCString(e->ctx, v);
  char *out = strdup(s ? s : "[]");
  if (s) JS_FreeCString(e->ctx, s);
  JS_FreeValue(e->ctx, v);
  return out;
}

static int64_t mg_memory_used_impl(void *p) {
  mg_engine *e = (mg_engine *)p;
  JSMemoryUsage u;
  JS_ComputeMemoryUsage(e->rt, &u);
  return u.memory_used_size;
}

MG_EXPORT char *mg_run_jobs(void *p) {
  mg_engine *e = (mg_engine *)p;
  MG_ENTER(e);
  char *r = mg_run_jobs_impl(p);
  MG_LEAVE(e);
  return r;
}

MG_EXPORT char *mg_eval_script(void *p, const char *name, const char *src) {
  mg_engine *e = (mg_engine *)p;
  MG_ENTER(e);
  char *r = mg_eval_script_impl(p, name, src);
  MG_LEAVE(e);
  return r;
}

MG_EXPORT char *mg_eval_module(void *p, const char *name, const char *src) {
  mg_engine *e = (mg_engine *)p;
  MG_ENTER(e);
  char *r = mg_eval_module_impl(p, name, src);
  MG_LEAVE(e);
  return r;
}

MG_EXPORT char *mg_call_global(void *p, const char *fn, const char *json, const uint8_t *bytes,
                               int64_t nbytes) {
  mg_engine *e = (mg_engine *)p;
  MG_ENTER(e);
  char *r = mg_call_global_impl(p, fn, json, bytes, nbytes);
  MG_LEAVE(e);
  return r;
}

MG_EXPORT char *mg_export_names(void *p) {
  mg_engine *e = (mg_engine *)p;
  MG_ENTER(e);
  char *r = mg_export_names_impl(p);
  MG_LEAVE(e);
  return r;
}

MG_EXPORT int64_t mg_memory_used(void *p) {
  mg_engine *e = (mg_engine *)p;
  MG_ENTER(e);
  int64_t r = mg_memory_used_impl(p);
  MG_LEAVE(e);
  return r;
}
