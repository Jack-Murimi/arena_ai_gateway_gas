/// A delivery assigned to a rider.
class Delivery {
  const Delivery({
    required this.id,
    this.branchId,
    this.branchName,
    this.riderId,
    this.riderName,
    required this.customerName,
    this.location,
    this.amount = 0,
    this.status = 'pending',
    this.note,
    this.createdAt,
    this.deliveredAt,
  });

  final String id;
  final String? branchId;
  final String? branchName;
  final String? riderId;
  final String? riderName;
  final String customerName;
  final String? location;
  final double amount;
  final String status; // pending | assigned | picked_up | delivered | cancelled
  final String? note;
  final DateTime? createdAt;
  final DateTime? deliveredAt;

  bool get isPending =>
      status == 'pending' || status == 'assigned' || status == 'picked_up';
  bool get isDelivered => status == 'delivered';

  factory Delivery.fromMap(Map<String, dynamic> map) {
    final branch = map['branches'] as Map<String, dynamic>?;
    final rider = map['profiles'] as Map<String, dynamic>?;
    return Delivery(
      id: map['id'] as String,
      branchId: map['branch_id'] as String?,
      branchName: branch?['name'] as String?,
      riderId: map['rider_id'] as String?,
      riderName: rider?['full_name'] as String?,
      customerName: (map['customer_name'] as String?) ?? '',
      location: map['location'] as String?,
      amount: ((map['amount'] as num?) ?? 0).toDouble(),
      status: (map['status'] as String?) ?? 'pending',
      note: map['note'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      deliveredAt: map['delivered_at'] != null
          ? DateTime.tryParse(map['delivered_at'] as String)
          : null,
    );
  }
}
