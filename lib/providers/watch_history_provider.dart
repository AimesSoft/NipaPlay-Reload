import 'package:flutter/material.dart';
import '../models/watch_history_model.dart';

class WatchHistoryProvider extends ChangeNotifier {
  List<WatchHistoryItem> _history = [];
  bool _isLoading = false;
  bool _isLoaded = false;

  List<WatchHistoryItem> get history => _history;
  bool get isLoading => _isLoading;
  bool get isLoaded => _isLoaded;

  Future<void> loadHistory() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();
    try {
      _history = await WatchHistoryManager.getAllHistory();
      _isLoaded = true;
    } catch (e) {
      _history = [];
      _isLoaded = false;
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    await loadHistory();
  }
} 