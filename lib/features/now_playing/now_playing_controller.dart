import 'package:flutter/widgets.dart';

/// Now Playing's panes: the cover (phones), lyrics, the queue, comments.
enum NpPane { cover, lyrics, queue, comments }

/// Whether Now Playing is open, which pane it shows, and how far it has
/// grown out of the player (0 closed, 1 open), which the mini player and the
/// player bar follow to hide the cover that flies out of them.
class NowPlayingController extends ChangeNotifier {
  bool isOpen = false;
  NpPane pane = NpPane.cover;

  /// 0..1, set by the layer as it animates.
  final progress = ValueNotifier<double>(0);

  /// The cover in the mini player / player bar that Now Playing grows out of,
  /// and the bar itself (on a phone the whole card grows).
  final fromCoverKey = GlobalKey(debugLabel: 'np-from-cover');
  final fromBarKey = GlobalKey(debugLabel: 'np-from-bar');

  // The mini player's drag, handed to the layer, which owns the animation.
  void Function(double dy)? onDragUpdate;
  void Function(double velocity)? onDragEnd;

  void open({NpPane? pane}) {
    if (pane != null) this.pane = pane;
    isOpen = true;
    notifyListeners();
  }

  void close() {
    if (!isOpen) return;
    isOpen = false;
    notifyListeners();
  }

  /// Shows [p], cover or not.
  void show(NpPane p) {
    pane = p;
    notifyListeners();
  }

  /// Marks it open (the mini player's drag opened it).
  void markOpen() {
    if (isOpen) return;
    isOpen = true;
    notifyListeners();
  }

  /// Toggles [p]; choosing the pane shown goes back to the cover.
  void choose(NpPane p) {
    pane = pane == p && p != NpPane.cover ? NpPane.cover : p;
    notifyListeners();
  }
}

/// The app's one Now Playing (UI state, like the shell's).
final nowPlaying = NowPlayingController();
