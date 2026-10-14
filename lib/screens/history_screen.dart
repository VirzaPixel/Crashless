import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/road_damage.dart';
import '../services/supabase_service.dart';
import '../widgets/empty_state.dart';
import 'detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<RoadDamage> _damages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _isLoading = true);
    }

    try {
      final data = await SupabaseService.getRecentDetections(limit: 50);
      final damages = data.map((d) => RoadDamage.fromJson(d)).toList();

      if (mounted) {
        setState(() {
          _damages = damages;
          _isLoading = false;
        });
      }
    } catch (error) {
      debugPrint('❌ Error loading history: $error');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _refreshHistory() async {
    await _loadHistory(showLoading: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Riwayat Deteksi',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshHistory,
              child: _damages.isEmpty
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          children: [
                            SizedBox(
                              height: constraints.maxHeight,
                              child: const EmptyState(
                                icon: Icons.history,
                                title: 'Belum Ada Riwayat',
                                message:
                                    'Deteksi kerusakan jalan akan muncul di sini',
                              ),
                            ),
                          ],
                        );
                      },
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      itemCount: _damages.length,
                      itemBuilder: (context, index) {
                        final damage = _damages[index];
                        return TweenAnimationBuilder<double>(
                          duration: Duration(milliseconds: 300 + (index * 50)),
                          curve: Curves.easeOutCubic,
                          tween: Tween(begin: 0.0, end: 1.0),
                          builder: (context, value, child) {
                            return Transform.translate(
                              offset: Offset(0, 20 * (1 - value)),
                              child: Opacity(
                                opacity: value,
                                child: child,
                              ),
                            );
                          },
                          child: _buildDamageCard(damage),
                        );
                      },
                    ),
            ),
    );
  }

  Widget _buildDamageCard(RoadDamage damage) {
    // Simple date format without locale dependency
    final dateStr =
        '${damage.createdAt.day}/${damage.createdAt.month}/${damage.createdAt.year} ${damage.createdAt.hour}:${damage.createdAt.minute.toString().padLeft(2, '0')}';

    Color severityColor = Colors.grey;
    IconData severityIcon = Icons.info_outline;

    switch (damage.severity) {
      case 'high':
        severityColor = Colors.red;
        severityIcon = Icons.warning;
        break;
      case 'medium':
        severityColor = Colors.orange;
        severityIcon = Icons.error_outline;
        break;
      case 'low':
        severityColor = Colors.green;
        severityIcon = Icons.check_circle_outline;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DetailScreen(damage: damage),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image with severity badge
            Stack(
              children: [
                Hero(
                  tag: 'damage_${damage.id}',
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(16)),
                    child: CachedNetworkImage(
                      imageUrl: damage.imageUrl,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        height: 200,
                        color: Colors.grey[800],
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (context, url, error) => Container(
                        height: 200,
                        color: Colors.grey[800],
                        child: const Center(
                          child: Icon(Icons.broken_image,
                              size: 50, color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                ),

                // Severity badge
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: severityColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(severityIcon, color: Colors.white, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          damage.severity?.toUpperCase() ?? 'N/A',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Detection count badge
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning,
                            color: Colors.white, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '${damage.totalDetections}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Details
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date and time
                  Row(
                    children: [
                      Icon(Icons.access_time,
                          size: 16, color: Colors.grey[400]),
                      const SizedBox(width: 8),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[400],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Detection summary
                  Row(
                    children: [
                      Expanded(
                        child: _buildMiniStat(
                          'Lubang',
                          damage.potholesCount,
                          Colors.blue,
                          Icons.warning,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMiniStat(
                          'Retakan',
                          damage.cracksCount,
                          Colors.orange,
                          Icons.trending_down,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Location
                  if (damage.address != null) ...[
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.location_on,
                            size: 16, color: Colors.red[300]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            damage.address!,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[300],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, int count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[400],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
