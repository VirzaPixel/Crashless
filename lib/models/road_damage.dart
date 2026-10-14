class RoadDamage {
  final String id;
  final DateTime createdAt;
  final String imageUrl;
  final double? latitude;
  final double? longitude;
  final String? address;
  final int totalDetections;
  final int potholesCount;
  final int cracksCount;
  final List<DetectionData> detections;
  final String status;
  final String? severity;

  RoadDamage({
    required this.id,
    required this.createdAt,
    required this.imageUrl,
    this.latitude,
    this.longitude,
    this.address,
    required this.totalDetections,
    required this.potholesCount,
    required this.cracksCount,
    required this.detections,
    required this.status,
    this.severity,
  });

  factory RoadDamage.fromJson(Map<String, dynamic> json) {
    List<DetectionData> detectionsList = [];
    if (json['detections'] != null) {
      detectionsList = (json['detections'] as List)
          .map((d) => DetectionData.fromJson(d))
          .toList();
    }

    return RoadDamage(
      id: json['id'],
      createdAt: DateTime.parse(json['created_at']),
      imageUrl: json['image_url'],
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      address: json['address'],
      totalDetections: json['total_detections'] ?? 0,
      potholesCount: json['potholes_count'] ?? 0,
      cracksCount: json['cracks_count'] ?? 0,
      detections: detectionsList,
      status: json['status'] ?? 'pending',
      severity: json['severity'],
    );
  }

  String get severityColor {
    switch (severity) {
      case 'high':
        return 'red';
      case 'medium':
        return 'orange';
      case 'low':
        return 'green';
      default:
        return 'grey';
    }
  }
}

class DetectionData {
  final String label;
  final double confidence;
  final Map<String, double> box;

  DetectionData({
    required this.label,
    required this.confidence,
    required this.box,
  });

  factory DetectionData.fromJson(Map<String, dynamic> json) {
    return DetectionData(
      label: json['label'],
      confidence: json['confidence'].toDouble(),
      box: {
        'left': json['box']['left'].toDouble(),
        'top': json['box']['top'].toDouble(),
        'right': json['box']['right'].toDouble(),
        'bottom': json['box']['bottom'].toDouble(),
      },
    );
  }
}
