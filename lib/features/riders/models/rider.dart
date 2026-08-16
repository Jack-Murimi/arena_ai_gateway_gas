/// Aggregated rider info: profile + live delivery stats + monthly target.
class RiderSummary {
  const RiderSummary({
    required this.id,
    required this.fullName,
    this.phone,
    this.branchId,
    this.branchName,
    this.deliveredCount = 0,
    this.deliveredAmount = 0,
    this.pendingCount = 0,
    this.targetDeliveries = 0,
    this.targetAmount = 0,
  });

  final String id;
  final String fullName;
  final String? phone;
  final String? branchId;
  final String? branchName;
  final int deliveredCount;
  final double deliveredAmount;
  final int pendingCount;
  final int targetDeliveries;
  final double targetAmount;

  double get targetProgress => targetDeliveries > 0
      ? (deliveredCount / targetDeliveries).clamp(0.0, 1.0)
      : 0.0;

  String get initials {
    final parts =
        fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
