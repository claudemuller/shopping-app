class Item {
  String? id;
  String name;
  DateTime? lastSyncedAt;

  Item({this.id, required this.name, this.lastSyncedAt});

  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      id: json['id'],
      name: json['name'],
      lastSyncedAt: json['last_synced_at'] != null
          ? DateTime.parse(json['last_synced_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, String?> data = {
      'id': id,
      'name': name,
      'last_synced_at': lastSyncedAt?.toIso8601String(),
    };
    data.removeWhere((key, value) => value == null);
    return data;
  }
}
