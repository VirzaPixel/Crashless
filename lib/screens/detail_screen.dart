import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/road_damage.dart';

class DetailScreen extends StatefulWidget {
  final RoadDamage damage;

  const DetailScreen({super.key, required this.damage});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App Bar with Image
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag: 'damage_${widget.damage.id}',
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: widget.damage.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Colors.grey[800],
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: Colors.grey[800],
                        child: const Center(
                          child: Icon(Icons.broken_image,
                              size: 50, color: Colors.grey),
                        ),
                      ),
                    ),
                    // Gradient overlay
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 100,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.8),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Severity Badge
                  _buildSeverityBadge(),

                  const SizedBox(height: 20),

                  // Detection Summary
                  _buildDetectionSummary(),

                  const SizedBox(height: 24),

                  // Stats Cards
                  _buildStatsCards(),

                  const SizedBox(height: 24),

                  // Date & Time
                  _buildInfoSection(
                    icon: Icons.access_time,
                    title: 'Tanggal & Waktu',
                    content: _formatDate(widget.damage.createdAt),
                  ),

                  const SizedBox(height: 16),

                  // Location
                  if (widget.damage.address != null) ...[
                    _buildInfoSection(
                      icon: Icons.location_on,
                      title: 'Lokasi',
                      content: widget.damage.address!,
                    ),

                    const SizedBox(height: 16),

                    // Coordinates
                    if (widget.damage.latitude != null &&
                        widget.damage.longitude != null)
                      _buildInfoSection(
                        icon: Icons.gps_fixed,
                        title: 'Koordinat',
                        content:
                            '${widget.damage.latitude!.toStringAsFixed(6)}, ${widget.damage.longitude!.toStringAsFixed(6)}',
                      ),

                    const SizedBox(height: 24),
                  ],

                  // Detection Details List
                  _buildDetectionsList(),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeverityBadge() {
    Color severityColor = _getSeverityColor(widget.damage.severity);
    IconData severityIcon = _getSeverityIcon(widget.damage.severity);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: severityColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: severityColor, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(severityIcon, color: severityColor, size: 24),
          const SizedBox(width: 8),
          Text(
            'Tingkat: ${widget.damage.severity?.toUpperCase() ?? 'N/A'}',
            style: TextStyle(
              color: severityColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectionSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ringkasan Deteksi',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${widget.damage.totalDetections} kerusakan jalan terdeteksi pada gambar ini',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[400],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsCards() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Total',
            widget.damage.totalDetections,
            Colors.purple,
            Icons.warning_amber,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Lubang',
            widget.damage.potholesCount,
            Colors.blue,
            Icons.warning,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Retakan',
            widget.damage.cracksCount,
            Colors.orange,
            Icons.trending_down,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, int value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection({
    required IconData icon,
    required String title,
    required String content,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[700]!, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.blue, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[400],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectionsList() {
    if (widget.damage.detections.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Detail Deteksi',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...widget.damage.detections.asMap().entries.map((entry) {
          final index = entry.key + 1;
          final detection = entry.value;

          final labelText = switch (detection.label) {
            'pothole' => 'Jalan Berlubang',
            'manhole' => 'Manhole',
            _ => 'Retakan',
          };
          final color = switch (detection.label) {
            'pothole' => Colors.blue,
            'manhole' => Colors.purple,
            _ => Colors.orange,
          };
          final icon = switch (detection.label) {
            'pothole' => Icons.warning,
            'manhole' => Icons.circle_outlined,
            _ => Icons.trending_down,
          };

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[850],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.3), width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Center(
                    child: Icon(icon, color: color, size: 24),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$index. $labelText',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Confidence: ${(detection.confidence * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${(detection.confidence * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.greenAccent,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Color _getSeverityColor(String? severity) {
    switch (severity) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getSeverityIcon(String? severity) {
    switch (severity) {
      case 'high':
        return Icons.warning;
      case 'medium':
        return Icons.error_outline;
      case 'low':
        return Icons.check_circle_outline;
      default:
        return Icons.info_outline;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
