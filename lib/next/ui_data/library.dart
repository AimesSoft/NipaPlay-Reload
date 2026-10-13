/// What the library page reads: a corner menu of sources, each a page of
/// categories, each category a slice that loads as it scrolls.
///
/// A source shows either its own structure (Jellyfin's libraries and folders,
/// a share's folders) or the arrangement Nipa made for it on request; the
/// viewer can switch between them. Every string is shown as is.
library;

import 'ui_data.dart';

abstract interface class NextLibraryData {
  /// The corner menu: this device together with the mesh first, then each
  /// connected SMB, WebDAV, Jellyfin and Emby source.
  Future<List<UiLibrarySource>> sources();

  /// One source's page as it is arranged now. An offline source shows what
  /// was last seen of it; its works are not playable.
  Future<UiLibraryPage> page(String sourceId);

  /// Part of a category, for a grid that loads as it scrolls. [sort] is one
  /// of the category's [UiCategory.sorts] ids; null keeps the current one.
  Future<UiSlice> items(String categoryId,
      {int offset = 0, int limit = 60, String? sort});

  /// Fires when sources, arrangements or contents may have changed.
  Stream<void> get changes;
}

/// What the viewer changes directly. Anything else they ask Nipa for, who
/// arranges categories through the same body.
abstract interface class NextLibraryActions {
  Future<void> setForm(String sourceId, UiLibraryForm form);

  /// Shows the source's own structure, or Nipa's arrangement of it.
  Future<void> useOriginal(String sourceId, bool original);
  /// Moves a category to [index] among the page's categories.
  Future<void> moveCategory(String categoryId, int index);

  /// Takes a category off the page. In a source's own structure this only
  /// hides it in NipaPlay; nothing on the server or share changes.
  Future<void> removeCategory(String categoryId);

  /// Shows a hidden original category again ([UiLibraryPage.hiddenCategories]).
  Future<void> restoreCategory(String categoryId);
}

enum UiSourceKind { local, smb, webdav, jellyfin, emby, other }

/// Rows of previews, or a grid of category cards.
enum UiLibraryForm { shelves, cards }

final class UiLibrarySource {
  const UiLibrarySource({
    required this.sourceId,
    required this.name,
    required this.kind,
    this.online = true,
  });
  final String sourceId;

  /// “本地”, or the name the user gave the server or share.
  final String name;
  final UiSourceKind kind;
  final bool online;
}

final class UiLibraryPage {
  const UiLibraryPage({
    required this.form,
    this.categories = const [],
    this.arranged = false,
    this.hasArrangement = false,
    this.hiddenCategories = const [],
  });
  final UiLibraryForm form;

  /// True when Nipa's arrangement is shown, false for the source's own.
  final bool arranged;

  /// Whether Nipa has arranged this source, so there is something to switch
  /// to.
  final bool hasArrangement;

  /// In order. A page with a single category shows its items directly.
  final List<UiCategory> categories;

  /// Hidden original categories, with IDs accepted by ui.library.restore.
  /// Restoring them changes only this device's NipaPlay layout.
  final List<UiCategory> hiddenCategories;
}

final class UiCategory {
  const UiCategory({
    required this.categoryId,
    required this.title,
    this.count,
    this.posters = const [],
    this.backdrop,
    this.tint,
    this.preview = const [],
    this.sorts = const [],
  });
  final String categoryId;
  final String title;
  final int? count;

  /// Local poster paths for the cover, most representative first; a few at
  /// most.
  final List<String> posters;

  /// Local path of a wide image for the cover, when there is one.
  final String? backdrop;

  /// ARGB colour from the cover art, for gradients while images load.
  final int? tint;

  /// The first items, for a shelf row; may be empty in the cards form.
  final List<UiLibraryItem> preview;

  /// Ways to order it, the current one first.
  final List<UiSort> sorts;
}

final class UiSort {
  const UiSort(this.id, this.label);
  final String id;

  /// e.g. “最近添加”.
  final String label;
}

sealed class UiLibraryItem {
  const UiLibraryItem();
}

/// A work from any source. Its workId opens with [NextUiData.work] and
/// [NextUiData.episodes] and plays through the usual play action.
final class UiWorkItem extends UiLibraryItem {
  const UiWorkItem(this.work);
  final UiWork work;
}

/// A library, folder or collection from the source's own structure; it
/// opens as another category.
final class UiFolderItem extends UiLibraryItem {
  const UiFolderItem({
    required this.categoryId,
    required this.title,
    this.count,
    this.posters = const [],
  });
  final String categoryId;
  final String title;
  final int? count;
  final List<String> posters;
}

final class UiSlice {
  const UiSlice(this.items, {this.total});
  final List<UiLibraryItem> items;

  /// Items in the whole category, when the source knows.
  final int? total;
}
