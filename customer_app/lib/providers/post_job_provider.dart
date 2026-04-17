import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';

export '../core/category_catalog.dart'
    show labelForCategory, jobCategoryGroups, CategoryGroup, allCategoryOptions;

/// Draft data for the multi-step post-job flow (category → details → location → review).
class PostJobState {
  const PostJobState({
    this.category,
    this.title = '',
    this.description = '',
    this.address = '',
    this.locationLat = kAccraLat,
    this.locationLng = kAccraLng,
  });

  final String? category;
  final String title;
  final String description;
  final String address;
  final double locationLat;
  final double locationLng;

  PostJobState copyWith({
    String? category,
    bool clearCategory = false,
    String? title,
    String? description,
    String? address,
    double? locationLat,
    double? locationLng,
  }) {
    return PostJobState(
      category: clearCategory ? null : (category ?? this.category),
      title: title ?? this.title,
      description: description ?? this.description,
      address: address ?? this.address,
      locationLat: locationLat ?? this.locationLat,
      locationLng: locationLng ?? this.locationLng,
    );
  }
}

class PostJobNotifier extends StateNotifier<PostJobState> {
  PostJobNotifier() : super(const PostJobState());

  void reset() => state = const PostJobState();

  void setCategory(String category) => state = state.copyWith(category: category);

  void setDetails(String title, String description) =>
      state = state.copyWith(title: title, description: description);

  void setLocation(String address, double lat, double lng) => state = state.copyWith(
        address: address,
        locationLat: lat,
        locationLng: lng,
      );
}

final postJobProvider = StateNotifierProvider<PostJobNotifier, PostJobState>(
  (ref) => PostJobNotifier(),
);
