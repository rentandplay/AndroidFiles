import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../models/rental_model.dart';
import '../../services/auth_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String _selectedPeriod = 'Last 30 days';
  String _selectedCategory = 'All categories';
  String _selectedSubTab = 'Rental performance';

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Reports',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF64748B), size: 22),
            tooltip: 'Refresh',
            onPressed: () => setState(() {}),
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined, color: Color(0xFF64748B), size: 22),
            tooltip: 'Export CSV',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Exporting analytics CSV...')),
              );
            },
          ),
          const Padding(
            padding: EdgeInsets.only(right: 14.0),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xFFFED7AA),
              child: Text(
                'RP',
                style: TextStyle(
                  color: Color(0xFFC2410C),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('rentals').snapshots(),
        builder: (context, rentalSnap) {
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('items').snapshots(),
            builder: (context, itemSnap) {
              if (rentalSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              double confirmedFees = 0.0;
              int confirmedRentals = 0;
              int activeCount = 0;
              int totalCatalog = 14;

              if (rentalSnap.hasData && rentalSnap.data!.docs.isNotEmpty) {
                for (var doc in rentalSnap.data!.docs) {
                  final rental = RentalModel.fromMap(doc.data() as Map<String, dynamic>, id: doc.id);
                  if (rental.status == 'completed' || rental.status == 'active') {
                    confirmedFees += (rental.rateFee + rental.latePenalty);
                    confirmedRentals++;
                  }
                  if (rental.status == 'active') activeCount++;
                }
              }

              if (itemSnap.hasData && itemSnap.data!.docs.isNotEmpty) {
                totalCatalog = itemSnap.data!.docs.length;
              }

              double avgFee = confirmedRentals > 0 ? confirmedFees / confirmedRentals : 0.0;
              double utilization = totalCatalog > 0 ? (activeCount / totalCatalog) * 100 : 0.0;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Filter Controls Card
                    _buildFiltersCard(),

                    const SizedBox(height: 16),

                    // Timestamp Notice
                    const Text(
                      'Philippine time • Recorded rental fees exclude deposits. Today is a partial day.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    ),

                    const SizedBox(height: 16),

                    // 2. Sub-Navigation Tabs
                    _buildSubNavTabs(),

                    const SizedBox(height: 20),

                    // 3. Section Tag & Header
                    const Text(
                      '01 / DEMAND & INCOME',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF94A3B8),
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Rental performance',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 4. Performance Metric 2x2 Grid
                    _buildPerformanceGrid(
                      confirmedFees: confirmedFees,
                      confirmedRentals: confirmedRentals,
                      utilization: utilization,
                      avgFee: avgFee,
                      activeCount: activeCount,
                      totalCatalog: totalCatalog,
                    ),

                    const SizedBox(height: 20),

                    // 5. Revenue & Rentals Trends Section
                    _buildTrendCard(
                      title: 'Revenue trend',
                      subtitle: 'Confirmed rental fees • daily',
                      contentValue: '₱${confirmedFees.toStringAsFixed(2)}',
                      icon: Icons.show_chart,
                      color: const Color(0xFF0284C7),
                    ),

                    const SizedBox(height: 12),

                    _buildTrendCard(
                      title: 'Rentals trend',
                      subtitle: 'Confirmed rental count • daily',
                      contentValue: '$confirmedRentals rentals',
                      icon: Icons.bar_chart_rounded,
                      color: const Color(0xFF16A34A),
                    ),

                    const SizedBox(height: 24),

                    // 6. Connected Workspace Footer
                    _buildWorkspaceFooter(authService),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // --- FILTER CONTROLS ---
  Widget _buildFiltersCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Period', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _selectedPeriod,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: ['Last 30 days', 'Last 7 days', 'This Month']
                          .map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 12))))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedPeriod = val);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Category', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _selectedCategory,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: ['All categories', 'Sports', 'Cards', 'Board Games', 'Tech Rentals']
                          .map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12))))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedCategory = val);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF57C00),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Exporting analytics CSV...')),
                );
              },
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Export analytics CSV', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // --- SUB NAV TABS ---
  Widget _buildSubNavTabs() {
    final tabs = [
      'Rental performance',
      'Equipment insights',
      'Service & operations',
      'Definitions & coverage'
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: tabs.map((tab) {
            final isSelected = _selectedSubTab == tab;
            return GestureDetector(
              onTap: () => setState(() => _selectedSubTab = tab),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFFEF3EA) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  tab,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? const Color(0xFFC2410C) : const Color(0xFF64748B),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // --- PERFORMANCE GRID ---
  Widget _buildPerformanceGrid({
    required double confirmedFees,
    required int confirmedRentals,
    required double utilization,
    required double avgFee,
    required int activeCount,
    required int totalCatalog,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'Confirmed rental fees',
                value: '₱${confirmedFees.toStringAsFixed(2)}',
                subtitle: 'Recorded charges in period',
                topBorderColor: const Color(0xFFF57C00),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                title: 'Confirmed rentals',
                value: '$confirmedRentals',
                subtitle: 'Based on rental confirmation',
                topBorderColor: const Color(0xFF0284C7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'Equipment utilization',
                value: '${utilization.toStringAsFixed(0)}%',
                subtitle: '$activeCount rented / $totalCatalog items',
                topBorderColor: const Color(0xFF16A34A),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                title: 'Average fee / rental',
                value: '₱${avgFee.toStringAsFixed(2)}',
                subtitle: 'Confirmed fees ÷ rentals',
                topBorderColor: const Color(0xFFD97706),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required Color topBorderColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 3,
            width: double.infinity,
            decoration: BoxDecoration(
              color: topBorderColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }

  // --- TREND CARDS ---
  Widget _buildTrendCard({
    required String title,
    required String subtitle,
    required String contentValue,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              Icon(icon, color: color, size: 24),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Daily Summary:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                Text(
                  contentValue,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- WORKSPACE FOOTER ---
  Widget _buildWorkspaceFooter(AuthService authService) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF16A34A),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Connected workspace', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  Text('Cloud Firestore records', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                ],
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            children: [
              const CircleAvatar(
                radius: 16,
                backgroundColor: Color(0xFFFED7AA),
                child: Text('RP', style: TextStyle(color: Color(0xFFC2410C), fontWeight: FontWeight.bold, fontSize: 11)),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(authService.currentUser?.email ?? 'Reynold Pastor', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  const Text('ADMIN', style: TextStyle(fontSize: 10, color: Color(0xFFC2410C), fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
