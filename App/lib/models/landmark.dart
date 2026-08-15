class Landmark {
  final int id;
  final String title;
  final double lat;
  final double lon;
  final String image;
  final double score;
  final int visitCount;
  final double? avgDistance;

  Landmark({
    required this.id,
    required this.title,
    required this.lat,
    required this.lon,
    required this.image,
    required this.score,
    required this.visitCount,
    this.avgDistance,
  });

  factory Landmark.fromJson(Map<String, dynamic> j) {
    return Landmark(
      id: int.tryParse(j['id']?.toString() ?? '') ?? 0,
      title: j['title']?.toString() ?? '',
      lat: double.tryParse(j['lat']?.toString() ?? '') ?? 0.0,
      lon: double.tryParse(j['lon']?.toString() ?? '') ?? 0.0,
      image: j['image']?.toString() ?? '',
      score: double.tryParse(j['score']?.toString() ?? '') ?? 0.0,
      visitCount: int.tryParse(j['visit_count']?.toString() ?? '') ?? 0,
      avgDistance: j['avg_distance'] != null
          ? double.tryParse(j['avg_distance'].toString())
          : null,
    );
  }
}
