String maintenanceStageLabel(Map<dynamic, dynamic> row) {
  final status = row['status']?.toString().toUpperCase() ?? '';
  final stage = status == 'COMPLETED' || status == 'RETIRED'
      ? status
      : row['workflow_stage']?.toString().toUpperCase() ??
          (status == 'OPEN' ? 'REPORTED' : 'IN_REPAIR');
  return const {
        'REPORTED': 'Reported',
        'IN_REPAIR': 'In repair',
        'AWAITING_INSPECTION': 'For inspection',
        'COMPLETED': 'Completed',
        'RETIRED': 'Retired',
      }[stage] ??
      'Not recorded';
}
