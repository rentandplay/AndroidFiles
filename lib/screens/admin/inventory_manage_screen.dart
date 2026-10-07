import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/item_model.dart';

class InventoryManageScreen extends StatefulWidget {
  const InventoryManageScreen({super.key});

  @override
  State<InventoryManageScreen> createState() => _InventoryManageScreenState();
}

class _InventoryManageScreenState extends State<InventoryManageScreen> {
  String _selectedCategory = 'All';

  void _showAddEditItemDialog({ItemModel? item}) {
    final isEditing = item != null;
    final nameController = TextEditingController(text: item?.name ?? '');
    final descriptionController = TextEditingController(text: item?.description ?? '');
    final rateTextController = TextEditingController(text: item?.rateText ?? '');
    final rateHourlyController = TextEditingController(text: item?.rateHourly.toString() ?? '100');
    final depositController = TextEditingController(text: item?.deposit.toString() ?? '100');
    final specialRateController = TextEditingController(text: item?.specialRate ?? '');
    String category = item?.category ?? 'Sports';
    String status = item?.status ?? 'available';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isEditing ? 'Edit Inventory Item' : 'Add New Item',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Item Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: category,
                items: ['Sports', 'Cards', 'Board Games', 'Tech Rentals']
                    .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) category = val;
                },
                decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descriptionController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: rateTextController,
                decoration: const InputDecoration(labelText: 'Rate Display Text (e.g. ₱150/hr)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: rateHourlyController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Hourly Rate (₱)', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: depositController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Deposit (₱)', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Equipment item code', border: OutlineInputBorder()),
                child: Text(isEditing
                    ? (item?.qrCode ?? 'Assigned in the equipment inventory')
                    : 'Generated automatically as RENT-001, RENT-002, and so on'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: status,
                items: ['available', 'rented', 'maintenance']
                    .map((st) => DropdownMenuItem(value: st, child: Text(st.toUpperCase())))
                    .toList(),
                onChanged: (val) {
                  if (val != null) status = val;
                },
                decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF57C00),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () async {
                  final String newItemId = item?.id ?? 'item_${DateTime.now().millisecondsSinceEpoch}';

                  final newItem = ItemModel(
                    id: newItemId,
                    name: nameController.text.trim(),
                    category: category,
                    description: descriptionController.text.trim().isNotEmpty
                        ? descriptionController.text.trim()
                        : '${nameController.text.trim()} equipment rental item.',
                    rateText: rateTextController.text.trim(),
                    rateHourly: double.tryParse(rateHourlyController.text) ?? 100.0,
                    deposit: double.tryParse(depositController.text) ?? 100.0,
                    specialRate: specialRateController.text.trim().isNotEmpty ? specialRateController.text.trim() : null,
                    imageUrl: item?.imageUrl ?? 'assets/images/logo_rent_and_play.png',
                    status: status,
                    qrCode: item?.qrCode,
                  );

                  final itemRef = FirebaseFirestore.instance.collection('items').doc(newItemId);
                  if (isEditing) {
                    final itemData = newItem.toMap();
                    if (item?.qrCode != null) itemData['item_code'] = item!.qrCode;
                    await itemRef.set(itemData, SetOptions(merge: true));
                  } else {
                    final counterRef = FirebaseFirestore.instance.collection('counters').doc('item_codes_RENT');
                    final codeBase = FirebaseFirestore.instance.collection('item_codes');
                    await FirebaseFirestore.instance.runTransaction((transaction) async {
                      final counter = await transaction.get(counterRef);
                      final rawSequence = counter.data()?['next_sequence'];
                      final parsedSequence = rawSequence is int ? rawSequence : int.tryParse('$rawSequence') ?? 1;
                      final start = parsedSequence < 1 ? 1 : parsedSequence;
                      DocumentReference<Map<String, dynamic>>? codeRef;
                      var generatedCode = '';
                      var sequence = start;
                      for (var offset = 0; offset < 25; offset++) {
                        final candidateSequence = start + offset;
                        final candidate = 'RENT-${candidateSequence.toString().padLeft(3, '0')}';
                        final candidateRef = codeBase.doc(candidate);
                        final candidateSnapshot = await transaction.get(candidateRef);
                        if (!candidateSnapshot.exists) {
                          codeRef = candidateRef;
                          generatedCode = candidate;
                          sequence = candidateSequence;
                          break;
                        }
                      }
                      if (codeRef == null) throw StateError('Could not allocate an equipment code. Try again.');
                      final now = DateTime.now();
                      final itemData = newItem.toMap()
                        ..['item_code'] = generatedCode
                        ..['qrCode'] = generatedCode
                        ..['created_at'] = now
                        ..['updated_at'] = now;
                      transaction.set(codeRef, {'item_id': itemRef.id, 'created_at': now});
                      transaction.set(counterRef, {'next_sequence': sequence + 1, 'updated_at': now}, SetOptions(merge: true));
                      transaction.set(itemRef, itemData);
                    });
                  }

                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(isEditing ? 'Item updated!' : 'New item added!')),
                  );
                },
                child: Text(isEditing ? 'Save Changes' : 'Add Item'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Management'),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFF57C00),
        onPressed: () => _showAddEditItemDialog(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Column(
        children: [
          // Category filter
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: ['All', 'Sports', 'Cards', 'Board Games', 'Tech Rentals'].map((cat) {
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                  ),
                );
              }).toList(),
            ),
          ),

          // Items Stream
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('items').snapshots(),
              builder: (context, snapshot) {
                List<ItemModel> items = [];

                if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                  items = snapshot.data!.docs
                      .map((doc) => ItemModel.fromMap(doc.data() as Map<String, dynamic>, id: doc.id))
                      .toList();
                } else {
                  items = ItemModel.getInitialCatalog();
                }

                if (_selectedCategory != 'All') {
                  items = items.where((it) => it.category == _selectedCategory).toList();
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            _getCategoryIcon(item.category),
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                        title: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${item.category} • ${item.rateText}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: item.status == 'available'
                                    ? Colors.green.shade100
                                    : item.status == 'rented'
                                        ? Colors.orange.shade100
                                        : Colors.red.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                item.status.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: item.status == 'available'
                                      ? Colors.green.shade800
                                      : item.status == 'rented'
                                          ? Colors.orange.shade800
                                          : Colors.red.shade800,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20, color: Colors.blue),
                              tooltip: 'Edit Item',
                              onPressed: () => _showAddEditItemDialog(item: item),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Sports':
        return Icons.sports_basketball;
      case 'Cards':
        return Icons.style;
      case 'Board Games':
        return Icons.casino;
      case 'Tech Rentals':
        return Icons.sports_esports;
      default:
        return Icons.inventory_2;
    }
  }
}
