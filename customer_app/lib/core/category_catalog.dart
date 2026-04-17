import 'package:flutter/material.dart';

/// Grouped service categories (maps to API `JobCategory` enum strings).
class CategoryGroup {
  const CategoryGroup({
    required this.id,
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.entries,
  });

  final String id;
  final String title;
  final IconData icon;
  final Color accentColor;

  /// `(apiEnumId, displayLabel)`.
  final List<(String, String)> entries;
}

/// All groups + subcategories. IDs match [backend/prisma/schema.prisma] `JobCategory`.
final List<CategoryGroup> jobCategoryGroups = [
  CategoryGroup(
    id: 'home_repairs',
    title: 'Home & repairs',
    icon: Icons.home_repair_service_rounded,
    accentColor: const Color(0xFF5D4037),
    entries: [
      ('CLEANING', 'Cleaning'),
      ('LAUNDRY', 'Laundry'),
      ('FUMIGATION', 'Fumigation'),
      ('CARPENTER', 'Carpentry'),
      ('PLUMBER', 'Plumbing'),
      ('ELECTRICIAN', 'Electrical'),
      ('PAINTING', 'Painting'),
      ('TILING', 'Tiling'),
      ('ROOFING', 'Roofing'),
      ('MASONRY', 'Masonry'),
      ('WELDING', 'Welding'),
      ('GLASS_ALUMINIUM', 'Glass / Aluminium'),
      ('INTERIOR_DESIGN', 'Interior design'),
      ('CCTV', 'CCTV'),
    ],
  ),
  CategoryGroup(
    id: 'appliance_tech',
    title: 'Appliance & tech',
    icon: Icons.kitchen_rounded,
    accentColor: const Color(0xFF0277BD),
    entries: [
      ('AC_REPAIR', 'AC'),
      ('FRIDGE', 'Fridge'),
      ('WASHING_MACHINE', 'Washing machine'),
      ('GENERATOR', 'Generator'),
      ('ELECTRONICS', 'Electronics'),
      ('PHONE_LAPTOP', 'Phone / Laptop'),
      ('SOLAR', 'Solar'),
    ],
  ),
  CategoryGroup(
    id: 'vehicle',
    title: 'Vehicle',
    icon: Icons.directions_car_rounded,
    accentColor: const Color(0xFF455A64),
    entries: [
      ('MECHANIC', 'Mechanic'),
      ('AUTO_ELECTRICIAN', 'Auto electrician'),
      ('CAR_AC', 'Car AC'),
      ('TYRE', 'Tyre'),
      ('CAR_WASH', 'Car wash'),
      ('TOWING', 'Towing'),
      ('DRIVING_LESSONS', 'Driving lessons'),
    ],
  ),
  CategoryGroup(
    id: 'beauty_wellness',
    title: 'Beauty & wellness',
    icon: Icons.spa_rounded,
    accentColor: const Color(0xFFAD1457),
    entries: [
      ('HAIRDRESSING', 'Hairdressing'),
      ('BARBERING', 'Barbering'),
      ('MAKEUP', 'Makeup'),
      ('NAILS', 'Nails'),
      ('MASSAGE', 'Massage'),
      ('FITNESS', 'Fitness'),
      ('TATTOO', 'Tattoo'),
    ],
  ),
  CategoryGroup(
    id: 'events',
    title: 'Events',
    icon: Icons.celebration_rounded,
    accentColor: const Color(0xFF6A1B9A),
    entries: [
      ('CATERING', 'Catering'),
      ('DJ', 'DJ'),
      ('MC', 'MC'),
      ('PHOTOGRAPHY', 'Photography'),
      ('VIDEOGRAPHY', 'Videography'),
      ('DECORATION', 'Decoration'),
      ('SOUND', 'Sound'),
      ('TENT_CHAIR', 'Tent / Chair'),
      ('BAND', 'Band'),
    ],
  ),
  CategoryGroup(
    id: 'education',
    title: 'Education',
    icon: Icons.school_rounded,
    accentColor: const Color(0xFF1565C0),
    entries: [
      ('TUTORING', 'Tutoring'),
      ('LANGUAGES', 'Languages'),
      ('MUSIC_LESSONS', 'Music lessons'),
      ('CHILDMINDING', 'Childminding'),
      ('SPECIAL_NEEDS', 'Special needs'),
    ],
  ),
  CategoryGroup(
    id: 'business_digital',
    title: 'Business & digital',
    icon: Icons.business_center_rounded,
    accentColor: const Color(0xFF2E7D32),
    entries: [
      ('GRAPHIC_DESIGN', 'Graphic design'),
      ('WEB_DEV', 'Web dev'),
      ('SOCIAL_MEDIA', 'Social media'),
      ('VIDEO_EDITING', 'Video editing'),
      ('PRINTING', 'Printing'),
      ('ACCOUNTING', 'Accounting'),
      ('LEGAL', 'Legal'),
      ('TRANSLATION', 'Translation'),
    ],
  ),
  CategoryGroup(
    id: 'logistics',
    title: 'Logistics',
    icon: Icons.local_shipping_rounded,
    accentColor: const Color(0xFFEF6C00),
    entries: [
      ('MOVING', 'Moving'),
      ('DELIVERY', 'Delivery'),
      ('TRUCK_HIRE', 'Truck hire'),
    ],
  ),
  CategoryGroup(
    id: 'other',
    title: 'Other',
    icon: Icons.more_horiz_rounded,
    accentColor: const Color(0xFF546E7A),
    entries: [
      ('OTHER', 'Other'),
    ],
  ),
];

/// Flat list for lookups / validation.
List<(String, String)> get allCategoryOptions {
  final out = <(String, String)>[];
  for (final g in jobCategoryGroups) {
    out.addAll(g.entries);
  }
  return out;
}

String labelForCategory(String? id) {
  if (id == null || id.isEmpty) return '—';
  for (final e in allCategoryOptions) {
    if (e.$1 == id) return e.$2;
  }
  return id.replaceAll('_', ' ');
}
