import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../services/admin_firestore_service.dart';
import '../../providers/theme_provider.dart';
import '../shared/equipment_qr_label_dialog.dart';

class AdminModuleView extends StatefulWidget {
  const AdminModuleView(
      {super.key,
      required this.page,
      required this.dashboard,
      required this.workspace,
      required this.inventory,
      required this.loading,
      required this.onNavigate,
      required this.onRefresh,
      required this.onChanged,
      required this.onInventoryRefresh,
      required this.onSignOut});
  final String page;
  final Map<String, dynamic> dashboard, workspace, inventory;
  final bool loading;
  final ValueChanged<String> onNavigate;
  final Future<void> Function() onRefresh,
      onChanged,
      onInventoryRefresh,
      onSignOut;
  @override
  State<AdminModuleView> createState() => _AdminModuleViewState();
}

class _AdminModuleViewState extends State<AdminModuleView> {
  final api = AdminFirestoreService.instance;
  String query = '', dashboardQuery = '', filter = 'All', scope = 'Active';
  bool busy = false;
  List<Map<String, dynamic>> rows(dynamic x) => x is List
      ? x.whereType<Map>().map(map).toList()
      : <Map<String, dynamic>>[];
  Map<String, dynamic> map(dynamic x) => x is Map<String, dynamic>
      ? x
      : x is Map
          ? x.map((k, v) => MapEntry('$k', v))
          : <String, dynamic>{};
  String s(dynamic x) => x == null ? '' : x.toString();
  double n(dynamic x) => x is num ? x.toDouble() : double.tryParse(s(x)) ?? 0;
  int i(dynamic x) => x is num ? x.toInt() : int.tryParse(s(x)) ?? 0;
  Map<String, dynamic> get inventory => widget.inventory;

  List<Map<String, dynamic>> get items => rows(inventory['items']);
  List<Map<String, dynamic>> get customers => rows(workspace['customers']);
  List<Map<String, dynamic>> get rentals => rows(workspace['transactions']);
  List<Map<String, dynamic>> get checks => rows(workspace['verification']);
  List<Map<String, dynamic>> get terminals => rows(workspace['terminals']);
  List<Map<String, dynamic>> get products =>
      rows(map(workspace['pricing'])['products']);
  Map<String, dynamic> get workspace => widget.workspace;
  @override
  Widget build(BuildContext c) {
    if (widget.loading && workspace.isEmpty)
      return const Center(child: CircularProgressIndicator());
    return switch (widget.page) {
      'Dashboard' => dashboard(),
      'Equipment' => equipment(),
      'Customers' => customerPage(),
      'Rates & Fees' => rates(),
      'Rentals' => transactionPage('Rentals'),
      'Returns' => transactionPage('Returns'),
      'Transaction History' => transactionPage('Transaction History'),
      'Maintenance' => maintenance(),
      'ESP32 / Verification' => verificationPage(),
      'Reports' => reports(),
      'Settings' => settings(),
      'Admin settings' => adminSettings(),
      'Profile' => profile(),
      _ => dashboard()
    };
  }

  Widget dashboard() {
    final stats = map(widget.dashboard['stats']),
        rev = map(widget.dashboard['revenue']);
    final bars = rev['This week'] is List
        ? (rev['This week'] as List).map(n).toList()
        : List<double>.filled(7, 0);
    final open = rows(widget.dashboard['rentals'])
        .where((x) => ['ACTIVE', 'PENDING_VERIFICATION'].contains(x['status']))
        .toList();
    final activeItems = rows(workspace['items'])
        .where((item) => item['is_active'] != false)
        .toList();
    final categoryRows = rows(workspace['categories']);
    final filteredOpen = open.where((rental) {
      final searchText = [
        rental['item_name'],
        rental['customer_name'],
        rental['rental_code'],
      ].join(' ').toLowerCase();
      return searchText.contains(dashboardQuery.toLowerCase());
    }).toList();
    final hero = LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 520;
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E8),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              right: compact ? -26 : 20,
              top: compact ? 8 : -6,
              child: IgnorePointer(
                child: Icon(
                  Icons.sports_basketball_rounded,
                  size: compact ? 125 : 178,
                  color: Clr.orange.withValues(alpha: .14),
                ),
              ),
            ),
            SizedBox(
              width: compact ? constraints.maxWidth - 62 : 560,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'YOUR DAILY GAME PLAN',
                    style: TextStyle(
                      color: Clr.orange,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'More play. Less paperwork.',
                    style: TextStyle(
                      fontSize: compact ? 23 : 28,
                      height: 1.15,
                      fontWeight: FontWeight.w900,
                      color: Clr.ink,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'A clear view of your rentals, so you can focus on the fun.',
                    style: TextStyle(color: Clr.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => widget.onNavigate('Rentals'),
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('Rental workflow'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Clr.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });

    final rentalsPanel = panel(
      'Rentals to keep an eye on',
      'Open rentals and requests waiting for counter confirmation.',
      Column(children: [
        TextField(
          onChanged: (value) => setState(() => dashboardQuery = value),
          decoration: InputDecoration(
            hintText: 'Search item, customer, or rental ID',
            prefixIcon: const Icon(Icons.search, size: 20),
            filled: true,
            fillColor: Clr.canvas,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (filteredOpen.isEmpty)
          empty(
            open.isEmpty ? 'No open rentals' : 'No matching rentals',
            open.isEmpty
                ? 'New requests will appear here.'
                : 'Try a different item, customer, or rental ID.',
          )
        else
          for (final rental in filteredOpen.take(8))
            rentalTile(rental, compact: true),
        TextButton(
          onPressed: () => widget.onNavigate('Rentals'),
          child: const Text('View all rentals'),
        ),
      ]),
    );

    final revenuePanel = panel(
      'Confirmed rental fees',
      'This week · refundable deposits excluded',
      revenue(bars),
    );

    final categoryPanel = panel(
      'A little of everything',
      'Your equipment at a glance.',
      Column(children: [
        if (categoryRows.isEmpty)
          empty('No categories yet', 'Equipment categories will appear here.')
        else
          for (final category in categoryRows.take(5))
            InkWell(
              onTap: () => widget.onNavigate('Equipment'),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0E4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.sports_basketball_outlined,
                      color: Clr.orange,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s(category['name']).isEmpty
                              ? 'Uncategorized'
                              : s(category['name']),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Clr.ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${activeItems.where((item) => s(item['category_id']) == s(category['id'])).length} items in inventory',
                          style: const TextStyle(
                            color: Clr.muted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward,
                      size: 16, color: Clr.muted),
                ]),
              ),
            ),
      ]),
    );

    final counterTip = Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8EC),
        border: Border.all(color: const Color(0xFFF4E7D1)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, color: Clr.orange, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('A small counter tip',
                    style: TextStyle(
                        color: Clr.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w900)),
                SizedBox(height: 3),
                Text('Check item condition before confirming a return.',
                    style: TextStyle(color: Clr.muted, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );

    return col([
      hero,
      metrics([
        M('Active rentals', s(stats['active'] ?? open.length), 'Currently out',
            Icons.schedule, Clr.blue),
        M('Available items', s(stats['available'] ?? '—'), 'Ready to rent',
            Icons.inventory_2, Clr.green),
        M('Due today', s(stats['dueToday'] ?? '—'),
            s(stats['overdue'] ?? 0) + ' overdue', Icons.today, Clr.amber),
        M('Rental fees', money(stats['fees']), 'Active charges', Icons.payments,
            Clr.purple)
      ]),
      LayoutBuilder(
          builder: (c, b) => b.maxWidth < 760
              ? Column(children: [
                  rentalsPanel,
                  revenuePanel,
                  terminalPanel(),
                  categoryPanel,
                  counterTip,
                ])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: Column(children: [rentalsPanel, revenuePanel]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 5,
                      child: Column(children: [
                        terminalPanel(),
                        categoryPanel,
                        counterTip,
                      ]),
                    ),
                  ],
                )),
    ]);
  }

  Widget revenue(List<double> a) {
    final total = a.fold<double>(0, (x, y) => x + y);
    return Column(children: [
      Text(money(total),
          style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
      const Text('Confirmed rental fees', style: TextStyle(color: Clr.muted)),
      SizedBox(height: 110, child: CustomPaint(painter: BarChart(a)))
    ]);
  }

  Widget terminalPanel() {
    final ts = rows(widget.dashboard['terminals']),
        pending = rows(widget.dashboard['pending']),
        t = ts.isEmpty ? <String, dynamic>{} : ts.first;
    final online = t['online'] == true || t['status'] == 'ONLINE';
    return panel(
        'Counter terminal',
        'Physical confirmation status',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                  color: Clr.navy, borderRadius: BorderRadius.circular(14)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        s(t['terminal_code']).isEmpty
                            ? 'NO TERMINAL REGISTERED'
                            : s(t['terminal_code']),
                        style: const TextStyle(color: Colors.white70)),
                    Text(online ? 'ONLINE' : 'OFFLINE',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900)),
                    Text(s(t['name']))
                  ])),
          rowData('Pending verification', pending.length),
          rowData('Last seen', date(t['last_seen_at'])),
          OutlinedButton.icon(
              onPressed: () => widget.onNavigate('ESP32 / Verification'),
              icon: const Icon(Icons.memory),
              label: const Text('Verification activity'))
        ]));
  }

  Widget equipment() {
    final all = items, cats = rows(widget.inventory['categories']);
    final visible = all.where((x) {
      final active = x['is_active'] != false,
          text = [x['name'], x['item_code'], x['category'], x['description']]
              .join(' ')
              .toLowerCase(),
          st = s(x['effective_status'] ?? x['status']);
      return (scope == 'Archived' ? !active : active) &&
          (filter == 'All' || filter == st) &&
          text.contains(query.toLowerCase());
    }).toList();
    return col([
      title(
          'Equipment',
          'Manage inventory, rates, condition, and availability.',
          FilledButton.icon(
              onPressed: () => editItem(cats),
              icon: const Icon(Icons.add),
              label: const Text('Add equipment'))),
      metrics([
        M('Equipment', all.length.toString(), 'All inventory',
            Icons.inventory_2, Clr.blue),
        M(
            'Available',
            all.where((x) => x['status'] == 'AVAILABLE').length.toString(),
            'Ready to rent',
            Icons.check_circle,
            Clr.green),
        M('Rented', all.where((x) => x['status'] == 'RENTED').length.toString(),
            'Currently out', Icons.schedule, Clr.blue),
        M(
            'Maintenance',
            all
                .where((x) => x['status'] == 'UNDER_MAINTENANCE')
                .length
                .toString(),
            'Being serviced',
            Icons.build,
            Clr.amber)
      ]),
      panel(
          'Equipment collection',
          'Search active items or review archived equipment.',
          Column(children: [
            search('Search name, code, or category'),
            SegmentedButton<String>(segments: const [
              ButtonSegment(value: 'Active', label: Text('Active')),
              ButtonSegment(value: 'Archived', label: Text('Archived'))
            ], selected: {
              scope
            }, onSelectionChanged: (v) => setState(() => scope = v.first)),
            chips([
              'All',
              'AVAILABLE',
              'RENTED',
              'UNDER_MAINTENANCE',
              'RESERVED_PENDING'
            ]),
            if (visible.isEmpty)
              empty('No equipment matches', 'Try another search or filter.')
            else
              for (final x in visible) itemTile(x)
          ]),
          trailing: IconButton(
              onPressed: () => categoryManager(cats),
              icon: const Icon(Icons.category))),
    ]);
  }

  Widget itemTile(Map<String, dynamic> x) => card(Column(children: [
        Row(children: [
          itemIcon(s(x['category'])),
          const SizedBox(width: 8),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(s(x['name']),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(s(x['item_code']) + ' · ' + s(x['category']),
                    style: const TextStyle(color: Clr.muted, fontSize: 11))
              ])),
          badge(label(x['effective_status'] ?? x['status'])),
          PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit')
                  editItem(rows(widget.inventory['categories']), item: x);
                if (v == 'qr') showQr(x);
                if (v == 'archive' || v == 'restore') itemAction(x, v);
                if (v == 'maintenance' || v == 'complete-maintenance')
                  maintenanceAction(x, v);
              },
              itemBuilder: (_) => [
                    if (x['is_active'] != false)
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(value: 'qr', child: Text('QR code')),
                    if (x['status'] == 'AVAILABLE')
                      const PopupMenuItem(
                          value: 'maintenance',
                          child: Text('Start maintenance')),
                    if (x['status'] == 'UNDER_MAINTENANCE')
                      const PopupMenuItem(
                          value: 'complete-maintenance',
                          child: Text('Complete maintenance')),
                    if (x['is_active'] == false)
                      const PopupMenuItem(
                          value: 'restore', child: Text('Restore')),
                    if (x['is_active'] != false)
                      const PopupMenuItem(
                          value: 'archive', child: Text('Archive'))
                  ])
        ]),
        Wrap(spacing: 12, children: [
          fact('Rate', money(x['rental_rate']) + ' ' + label(x['rate_type'])),
          fact('Deposit', money(x['deposit_amount'])),
          fact('Condition', label(x['condition_status']))
        ])
      ]));
  Future<void> editItem(List<Map<String, dynamic>> cats,
      {Map<String, dynamic>? item}) async {
    if (cats.isEmpty) return toast('Add a category first.');
    var current = item ?? <String, dynamic>{};
    if (item != null) {
      try {
        current =
            map((await api.getMap('/inventory/' + s(item['id'])))['item']);
      } on AdminApiException catch (e) {
        return toast(e.message);
      }
    }
    final v = await form(item == null ? 'Add equipment' : 'Edit equipment', [
      Field('name', 'Equipment name', initial: s(current['name'])),
      Field('categoryId', 'Category',
          initial: s(current['category_id']),
          options: {for (final x in cats) s(x['id']): s(x['name'])}),
      Field('condition', 'Condition',
          initial: s(current['condition_status']).isEmpty
              ? 'GOOD'
              : s(current['condition_status']),
          options: const {
            'GOOD': 'Good',
            'FAIR': 'Fair',
            'DAMAGED': 'Damaged',
            'NEEDS_INSPECTION': 'Needs inspection'
          }),
      Field('rateType', 'Rate basis',
          initial: s(current['rate_type']).isEmpty
              ? 'HOURLY'
              : s(current['rate_type']),
          options: const {
            'HOURLY': 'Hourly',
            'DAILY': 'Daily',
            'FLAT': 'Flat'
          }),
      Field('rentalRate', 'Rate',
          initial: s(current['rental_rate']), numeric: true),
      Field('deposit', 'Deposit',
          initial: s(current['deposit_amount'] ?? 0), numeric: true),
      Field('latePenalty', 'Late penalty',
          initial: s(current['late_penalty_rate'] ?? 0), numeric: true),
      Field('pricingProductId', 'Client rate sheet',
          initial: s(current['pricing_product_id']),
          options: {
            '': 'None',
            for (final p in products) s(p['id']): s(p['name'])
          }),
      Field('description', 'Description',
          initial: s(current['description']), multiline: true, optional: true),
    ]);
    if (!mounted || v == null) return;
    String? image;
    final choosePhoto = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Equipment photo'),
                content: const Text('Add or replace the equipment photo?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Keep current')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Choose photo'))
                ]));
    if (!mounted) return;
    if (choosePhoto == true) {
      final f = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 1000, imageQuality: 65);
      if (!mounted) return;
      if (f != null) {
        final ext = f.name.split('.').last.toLowerCase(),
            mime = ext == 'png'
                ? 'png'
                : ext == 'webp'
                    ? 'webp'
                    : 'jpeg';
        image = 'data:image/' +
            mime +
            ';base64,' +
            base64Encode(await f.readAsBytes());
        if (image.length > 250000) return toast('Photo limit is 250 KB.');
      }
    }
    await mutate(() async {
      final body = <String, dynamic>{
        'name': v['name'],
        'categoryId': v['categoryId'],
        'condition': v['condition'],
        'rateType': v['rateType'],
        'rentalRate': n(v['rentalRate']),
        'deposit': n(v['deposit']),
        'latePenalty': n(v['latePenalty']),
        'pricingProductId': v['pricingProductId'],
        'description': v['description'],
        if (image != null) 'imageData': image
      };
      if (item == null) {
        await api.post('/inventory', body: body);
      } else {
        body['version'] = current['updated_at'];
        await api.patch('/inventory/' + s(item['id']), body: body);
      }
      await widget.onInventoryRefresh();
      await widget.onChanged();
    }, ok: item == null ? 'Equipment added.' : 'Equipment saved.');
  }

  Future<void> categoryManager(List<Map<String, dynamic>> cats) async {
    final add = await showModalBottomSheet<bool>(
        context: context,
        builder: (c) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const ListTile(title: Text('Categories')),
              for (final x in cats) ListTile(title: Text(s(x['name']))),
              ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Add category'),
                  onTap: () => Navigator.pop(c, true))
            ])));
    if (add != true) return;
    final v =
        await form('Add category', [const Field('name', 'Category name')]);
    if (v != null)
      await mutate(() async {
        await api.post('/item-categories', body: {'name': v['name']});
        await widget.onInventoryRefresh();
      }, ok: 'Category added.');
  }

  Future<void> itemAction(Map<String, dynamic> x, String action,
      {String? reason, String? condition}) async {
    await mutate(() async {
      final detail =
          map((await api.getMap('/inventory/' + s(x['id'])))['item']);
      await api.post('/inventory/' + s(x['id']) + '/actions', body: {
        'action': action,
        'version': detail['updated_at'],
        if (reason != null) 'reason': reason,
        if (condition != null) 'condition': condition
      });
      await widget.onInventoryRefresh();
      await widget.onChanged();
    }, ok: 'Equipment updated.');
  }

  Future<void> maintenanceAction(Map<String, dynamic> x, String action) async {
    final done = action == 'complete-maintenance',
        v = await form(done ? 'Complete maintenance' : 'Start maintenance', [
          Field('condition', 'Condition',
              initial: done ? 'GOOD' : 'FAIR',
              options: done
                  ? const {'GOOD': 'Good', 'FAIR': 'Fair'}
                  : const {
                      'GOOD': 'Good',
                      'FAIR': 'Fair',
                      'DAMAGED': 'Damaged',
                      'NEEDS_INSPECTION': 'Inspect'
                    }),
          Field('reason', done ? 'Inspection notes' : 'Maintenance reason',
              multiline: true)
        ]);
    if (v != null)
      await itemAction(x, action,
          reason: v['reason'], condition: v['condition']);
  }

  Widget customerPage() {
    final visible = customers.where((x) {
      final active = x['is_active'] != false,
          text = [x['full_name'], x['customer_code'], x['email'], x['phone']]
              .join(' ')
              .toLowerCase();
      return (scope == 'Archived' ? !active : active) &&
          text.contains(query.toLowerCase());
    }).toList();
    return col([
      title(
          'Customers',
          'Manage customer contacts and unique codes.',
          FilledButton.icon(
              onPressed: () => editCustomer(),
              icon: const Icon(Icons.person_add),
              label: const Text('Add customer'))),
      metrics([
        M(
            'Active',
            customers.where((x) => x['is_active'] != false).length.toString(),
            'Directory',
            Icons.people,
            Clr.blue),
        M(
            'Archived',
            customers.where((x) => x['is_active'] == false).length.toString(),
            'Can restore',
            Icons.archive,
            Clr.purple)
      ]),
      panel(
          'Customer directory',
          'Search name, code, email, or phone.',
          Column(children: [
            search('Search customer details'),
            SegmentedButton<String>(segments: const [
              ButtonSegment(value: 'Active', label: Text('Active')),
              ButtonSegment(value: 'Archived', label: Text('Archived'))
            ], selected: {
              scope
            }, onSelectionChanged: (v) => setState(() => scope = v.first)),
            if (visible.isEmpty)
              empty('No customers found', 'Try another search.')
            else
              for (final x in visible) customerTile(x)
          ]))
    ]);
  }

  Widget customerTile(Map<String, dynamic> x) => card(ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Text(initials(s(x['full_name'])))),
      title: Text(s(x['full_name']),
          style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(
          s(x['customer_code']) + ' · ' + s(x['phone'] ?? x['email']),
          style: const TextStyle(color: Clr.muted, fontSize: 11)),
      trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'edit')
              editCustomer(x);
            else
              mutate(() async {
                await api
                    .patch('/customers/' + s(x['id']), body: {'action': v});
                await widget.onChanged();
              }, ok: 'Customer updated.');
          },
          itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(
                    value: x['is_active'] == false ? 'restore' : 'archive',
                    child:
                        Text(x['is_active'] == false ? 'Restore' : 'Archive'))
              ])));
  Future<void> editCustomer([Map<String, dynamic>? x]) async {
    final v = await form(x == null ? 'Add customer' : 'Edit customer', [
      Field('fullName', 'Full name', initial: s(x?['full_name'])),
      Field('code', 'Customer code', initial: s(x?['customer_code'])),
      Field('email', 'Email',
          initial: s(x?['email']), email: true, optional: true),
      Field('phone', 'Phone', initial: s(x?['phone']), optional: true),
      Field('address', 'Address',
          initial: s(x?['address']), multiline: true, optional: true)
    ]);
    if (v == null) return;
    await mutate(() async {
      final b = {
        'fullName': v['fullName'],
        'code': v['code'],
        'email': v['email'],
        'phone': v['phone'],
        'address': v['address']
      };
      if (x == null) {
        await api.post('/customers', body: b);
      } else {
        await api.patch('/customers/' + s(x['id']), body: b);
      }
      await widget.onChanged();
    }, ok: x == null ? 'Customer added.' : 'Customer updated.');
  }

  Widget transactionPage(String kind) {
    final returned = rentals.where(isReturned).toList(),
        active = rentals.where((x) => x['status'] == 'ACTIVE').toList();
    final source = kind == 'Rentals'
        ? rentals
            .where(
                (x) => ['ACTIVE', 'PENDING_VERIFICATION'].contains(x['status']))
            .toList()
        : kind == 'Returns'
            ? returned
            : rentals;
    final visible = source
        .where((x) =>
            [x['rental_code'], x['item_name'], x['customer_name'], x['status']]
                .join(' ')
                .toLowerCase()
                .contains(query.toLowerCase()) &&
            (filter == 'All' ||
                label(x['status']) == filter ||
                rentalStatus(x) == filter))
        .toList();
    final action = kind == 'Rentals'
        ? FilledButton.icon(
            onPressed: () => request(returning: false),
            icon: const Icon(Icons.add),
            label: const Text('Request rental'))
        : kind == 'Returns'
            ? FilledButton.icon(
                onPressed: () => request(returning: true),
                icon: const Icon(Icons.assignment_return),
                label: const Text('Request return'))
            : OutlinedButton.icon(
                onPressed: () => copyCsv(visible),
                icon: const Icon(Icons.copy),
                label: const Text('Copy CSV'));
    return col([
      title(
          kind,
          kind == 'Rentals'
              ? 'Track open rentals and terminal requests.'
              : kind == 'Returns'
                  ? 'Review completed returns.'
                  : 'Search every rental stage.',
          action),
      metrics([
        M('Transactions', rentals.length.toString(), 'All rental records',
            Icons.receipt, Clr.blue),
        M('Active', active.length.toString(), 'Currently out', Icons.schedule,
            Clr.green),
        M('Returned', returned.length.toString(), 'Confirmed handoffs',
            Icons.assignment_return, Clr.purple),
        M(
            'Pending terminal',
            rentals
                .where((x) => x['status'] == 'PENDING_VERIFICATION')
                .length
                .toString(),
            'Awaiting confirmation',
            Icons.memory,
            Clr.amber)
      ]),
      if (kind == 'Returns')
        panel(
            'Return desk',
            'Physical confirmation required.',
            Column(children: [
              for (final x in pendingRequests('RETURN')) verificationTile(x),
              if (pendingRequests('RETURN').isEmpty)
                empty('No pending returns', 'New return requests appear here.')
            ])),
      panel(
          kind == 'Rentals'
              ? 'Open rentals'
              : kind == 'Returns'
                  ? 'Returned rentals'
                  : 'Transaction history',
          'Finalized at the counter terminal.',
          Column(children: [
            search('Search item, customer, or rental ID'),
            chips(kind == 'Rentals'
                ? ['All', 'ACTIVE', 'PENDING_VERIFICATION']
                : ['All', 'Returned', 'Returned late']),
            if (visible.isEmpty)
              empty('No matching transactions', 'Change search or filter.')
            else
              for (final x in visible.take(80)) rentalTile(x),
            if (visible.length > 80)
              TextButton(
                  onPressed: () => copyCsv(visible),
                  child: const Text('Copy all rows as CSV'))
          ]))
    ]);
  }

  Widget rentalTile(Map<String, dynamic> x, {bool compact = false}) =>
      card(InkWell(
          onTap: () => transactionDetail(x),
          child: Column(children: [
            Row(children: [
              itemIcon(s(x['category'])),
              const SizedBox(width: 8),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                        s(x['item_name']).isEmpty
                            ? 'Unknown equipment'
                            : s(x['item_name']),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(
                        s(x['rental_code'] ?? x['id']) +
                            ' · ' +
                            s(x['customer_name']),
                        style: const TextStyle(color: Clr.muted, fontSize: 11))
                  ])),
              badge(rentalStatus(x))
            ]),
            if (!compact)
              Wrap(spacing: 12, children: [
                fact('Due', date(x['due_at'])),
                fact('Fee', money(x['rental_fee'])),
                fact('Deposit', money(x['deposit_amount']))
              ]),
            Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () => transactionDetail(x),
                    child: const Text('Details')))
          ])));
  Future<void> request({required bool returning}) async {
    final ts = terminals
        .where((x) =>
            x['is_active'] != false && x['credentials_configured'] == true)
        .toList();
    if (ts.isEmpty)
      return toast('No configured counter terminal is available.');
    final fs = <Field>[];
    if (returning) {
      final open = rentals.where((x) => x['status'] == 'ACTIVE').toList();
      if (open.isEmpty) return toast('No active rentals to return.');
      fs.add(Field('rentalId', 'Active rental', options: {
        for (final x in open)
          s(x['id']): s(x['rental_code'] ?? x['id']) +
              ' · ' +
              s(x['item_name']) +
              ' · ' +
              s(x['customer_name'])
      }));
    } else {
      final available = items
              .where(
                  (x) => x['is_active'] != false && x['status'] == 'AVAILABLE')
              .toList(),
          cs = customers.where((x) => x['is_active'] != false).toList();
      if (available.isEmpty || cs.isEmpty)
        return toast('Available equipment and active customer required.');
      fs.add(Field('itemId', 'Equipment', options: {
        for (final x in available)
          s(x['id']): s(x['name']) + ' · ' + s(x['item_code'])
      }));
      fs.add(Field('customerId', 'Customer', options: {
        for (final x in cs)
          s(x['id']): s(x['full_name']) + ' · ' + s(x['customer_code'])
      }));
      fs.add(const Field('mode', 'Mode',
          initial: 'TIMED',
          options: {'TIMED': 'Timed rental', 'WHOLE_STAY': 'Whole stay'}));
      fs.add(const Field('durationMinutes', 'Duration minutes',
          initial: '60', numeric: true));
      fs.add(Field('resortCheckoutAt', 'Checkout ISO time',
          initial: DateTime.now()
              .add(const Duration(days: 1))
              .toUtc()
              .toIso8601String(),
          optional: true));
    }
    fs.add(Field('terminalId', 'Terminal', options: {
      for (final x in ts) s(x['id']): s(x['terminal_code'] ?? x['id'])
    }));
    fs.add(const Field('condition', 'Condition', initial: 'GOOD', options: {
      'GOOD': 'Good',
      'FAIR': 'Fair',
      'DAMAGED': 'Damaged',
      'NEEDS_INSPECTION': 'Needs inspection'
    }));
    fs.add(const Field('result', 'Result', initial: 'AVAILABLE', options: {
      'AVAILABLE': 'Available',
      'UNDER_MAINTENANCE': 'Under maintenance'
    }));
    fs.add(const Field('notes', 'Inspection notes', multiline: true));
    if (returning) {
      fs.add(const Field('penaltyAmount', 'Penalty (0 if none)',
          initial: '0', numeric: true));
      fs.add(const Field('penaltyReason', 'Penalty reason',
          optional: true, multiline: true));
    }
    final v = await form(returning ? 'Request return' : 'Request rental', fs);
    if (v == null) return;
    await mutate(() async {
      final ins = {
        'condition': v['condition'],
        'result': v['result'],
        'notes': v['notes']
      };
      final d = returning
          ? await api.post('/returns', body: {
              'rentalId': v['rentalId'],
              'terminalId': v['terminalId'],
              'inspection': ins,
              'penaltyAmount': n(v['penaltyAmount']),
              'penaltyReason': v['penaltyReason']
            })
          : await api.post('/rentals', body: {
              'itemId': v['itemId'],
              'customerId': v['customerId'],
              'terminalId': v['terminalId'],
              'mode': v['mode'],
              'durationMinutes': i(v['durationMinutes']),
              if (v['mode'] == 'WHOLE_STAY')
                'resortCheckoutAt': v['resortCheckoutAt'],
              'inspection': ins
            });
      await widget.onChanged();
      await requestResult(d, returning);
    }, ok: 'Request sent to terminal.');
  }

  Future<void> requestResult(Map<String, dynamic> d, bool returning) async {
    final r = map(d['request']),
        fee = map(d['fee_preview'] ?? map(d['rental'])['fee_breakdown']);
    if (!mounted) return;
    await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Awaiting terminal confirmation'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.memory, color: Clr.navy),
                  const Text('Verification code'),
                  SelectableText(s(r['verification_code']),
                      style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3)),
                  Text('Terminal ' +
                      s(r['terminal_code']) +
                      ' · ' +
                      date(r['expires_at'])),
                  rowData('Fee', money(fee['rental_fee'])),
                  rowData('Deposit', money(fee['deposit_amount'])),
                  rowData('Due', date(fee['due_at'])),
                  Text(
                      returning
                          ? 'Item remains rented until confirmation.'
                          : 'Item remains reserved until confirmation or expiry.',
                      style: const TextStyle(color: Clr.muted, fontSize: 11))
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Done'))
                ]));
  }

  Widget maintenance() {
    final list = rows(workspace['maintenance']);
    return col([
      title(
          'Maintenance',
          'Review equipment repair history.',
          TextButton(
              onPressed: () => widget.onNavigate('Equipment'),
              child: const Text('Equipment'))),
      metrics([
        M(
            'In progress',
            list
                .where((x) => ['OPEN', 'IN_PROGRESS'].contains(x['status']))
                .length
                .toString(),
            'Service work',
            Icons.build,
            Clr.amber),
        M(
            'Completed',
            list.where((x) => x['status'] == 'COMPLETED').length.toString(),
            'Jobs',
            Icons.check_circle,
            Clr.green),
        M('Total', list.length.toString(), 'Records', Icons.history, Clr.blue)
      ]),
      panel(
          'Maintenance log',
          'Manage work from Equipment.',
          list.isEmpty
              ? empty('No maintenance records',
                  'Equipment sent for service appears here.')
              : Column(children: [
                  for (final x in list)
                    ListTile(
                        leading: itemIcon(s(x['item_name'])),
                        title: Text(s(x['item_name'])),
                        subtitle: Text(s(x['reason'] ?? x['details']) +
                            ' · ' +
                            date(x['started_at'])),
                        trailing: badge(label(x['status'])))
                ]))
    ]);
  }

  List<Map<String, dynamic>> pendingRequests(String? type) => checks
      .where((x) =>
          x['status'] == 'PENDING' &&
          (type == null ||
              s(x['transaction_type'] ?? x['type']).toUpperCase() == type))
      .toList();
  Widget verificationPage() {
    final visible = checks
        .where((x) =>
            [
              x['id'],
              x['rental_id'],
              x['verification_code'],
              x['terminal_code'],
              x['item_name'],
              x['customer_name'],
              x['status']
            ].join(' ').toLowerCase().contains(query.toLowerCase()) &&
            (filter == 'All' || s(x['status']) == filter))
        .toList();
    return col([
      title('ESP32 / Verification', 'Inspect terminal requests and history.'),
      metrics([
        for (final st in ['PENDING', 'CONFIRMED', 'REJECTED', 'EXPIRED'])
          M(
              label(st),
              checks.where((x) => x['status'] == st).length.toString(),
              st == 'PENDING' ? 'Waiting at counter' : 'Recorded attempts',
              Icons.memory,
              status(st))
      ]),
      panel(
          'Verification queue',
          'Only the physical terminal can finalize.',
          Column(children: [
            for (final x in pendingRequests(null)) verificationTile(x),
            if (pendingRequests(null).isEmpty)
              empty('No pending handoffs', 'New requests appear here.')
          ])),
      panel(
          'Verification history',
          'All rental and return attempts.',
          Column(children: [
            search('Search request, code, or terminal'),
            chips(['All', 'PENDING', 'CONFIRMED', 'REJECTED', 'EXPIRED']),
            if (visible.isEmpty)
              empty('No matching attempts', 'Adjust search or filter.')
            else
              for (final x in visible) verificationTile(x)
          ])),
      panel(
          'Registered terminals',
          'Status from recent device polls.',
          Column(children: [
            for (final x in terminals)
              ListTile(
                  title: Text(s(x['terminal_code'] ?? x['id'])),
                  subtitle:
                      Text(s(x['name']) + ' · ' + date(x['last_seen_at'])),
                  trailing: badge(label(x['status'])))
          ]))
    ]);
  }

  Widget verificationTile(Map<String, dynamic> x) =>
      card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.memory, color: Clr.navy),
          Expanded(
              child: Text(
                  label(x['transaction_type'] ?? x['type']) + ' handoff',
                  style: const TextStyle(fontWeight: FontWeight.w800))),
          badge(label(x['status']))
        ]),
        Text(s(x['item_name'] ?? 'Equipment') +
            ' · ' +
            s(x['customer_name'] ?? 'Customer')),
        Text(
            'Deliver to: ' +
                s(x['deliveryLocation'] ?? x['delivery_location'] ?? x['resort'] ?? 'ASRI Hotspring Resort'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Clr.orange)),
        Text(
            'Code ' +
                s(x['verification_code']) +
                ' · ' +
                s(x['terminal_code'] ?? x['terminal_id']),
            style: const TextStyle(color: Clr.muted, fontSize: 11)),
        Text(
            'Requested ' +
                date(x['requested_at']) +
                ' · expires ' +
                date(x['expires_at']),
            style: const TextStyle(color: Clr.muted, fontSize: 11)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: () => showQr(x),
              icon: const Icon(Icons.print, size: 16, color: Clr.orange),
              label: const Text('Print QR Label',
                  style: TextStyle(color: Clr.orange, fontSize: 12)),
            ),
            const SizedBox(width: 8),
            if (x['status'] == 'PENDING')
              ElevatedButton.icon(
                onPressed: () => inspect(x),
                icon: const Icon(Icons.fact_check, size: 16),
                label: Text(
                  x['inspection'] == null
                      ? 'Record inspection'
                      : 'Review inspection',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ]));
  Future<void> inspect(Map<String, dynamic> x) async {
    final prev = map(x['inspection']),
        release =
            s(x['transaction_type'] ?? x['type']).toUpperCase() == 'RENTAL';
    final fs = <Field>[
      Field('condition', 'Condition',
          initial: s(prev['condition']).isEmpty ? 'GOOD' : s(prev['condition']),
          options: const {
            'GOOD': 'Good',
            'FAIR': 'Fair',
            'DAMAGED': 'Damaged',
            'NEEDS_INSPECTION': 'Needs inspection'
          }),
      Field('result', 'Result',
          initial: s(prev['result']).isEmpty ? 'AVAILABLE' : s(prev['result']),
          options: const {
            'AVAILABLE': 'Available',
            'UNDER_MAINTENANCE': 'Under maintenance'
          }),
      Field('notes', 'Inspection notes',
          initial: s(prev['notes']), multiline: true)
    ];
    if (!release) {
      fs.add(Field('penaltyAmount', 'Penalty (0 if none)',
          initial: s(x['penalty_amount'] ?? 0), numeric: true));
      fs.add(Field('penaltyReason', 'Penalty reason',
          optional: true, multiline: true));
    }
    final v = await form('Inspection', fs);
    if (v == null) return;
    await mutate(() async {
      await api
          .put('/verification-requests/' + s(x['id']) + '/inspection', body: {
        'revision': i(x['inspection_revision']),
        'condition': v['condition'],
        'result': v['result'],
        'notes': v['notes'],
        if (!release) 'penaltyAmount': n(v['penaltyAmount']),
        if (!release) 'penaltyReason': v['penaltyReason']
      });
      await widget.onChanged();
    }, ok: 'Inspection saved; terminal confirmation required.');
  }

  Future<void> transactionDetail(Map<String, dynamic> x) async {
    final related =
            checks.where((r) => s(r['rental_id']) == s(x['id'])).toList(),
        fee = map(x['fee_breakdown']);
    if (!mounted) return;
    await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text(s(x['rental_code']).isEmpty
                    ? 'Rental details'
                    : s(x['rental_code'])),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  rowData('Equipment', x['item_name']),
                  rowData('Customer', x['customer_name']),
                  rowData('Delivery Resort', x['deliveryLocation'] ?? x['delivery_location'] ?? x['resort'] ?? 'ASRI Hotspring Resort'),
                  rowData('Status', rentalStatus(x)),
                  rowData('Rented',
                      date(x['confirmed_rental_at'] ?? x['created_at'])),
                  rowData('Due', date(x['due_at'])),
                  rowData('Returned', date(x['confirmed_return_at'])),
                  rowData('Rental fee', money(x['rental_fee'])),
                  rowData('Deposit', money(x['deposit_amount'])),
                  if (fee.isNotEmpty)
                    rowData(
                        'Final charges', money(fee['final_rental_charges'])),
                  for (final r in related)
                    ListTile(
                        title: Text(label(r['type'] ?? r['transaction_type']) +
                            ' · ' +
                            label(r['status'])),
                        subtitle: Text(s(r['verification_code']) +
                            ' · ' +
                            date(r['requested_at'])),
                        trailing: r['status'] == 'PENDING'
                            ? IconButton(
                                icon: const Icon(Icons.fact_check),
                                onPressed: () {
                                  Navigator.pop(c);
                                  inspect(r);
                                })
                            : null)
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Close'))
                ]));
  }

  Widget rates() {
    final pricing = map(workspace['pricing']),
        rules = map(map(workspace['pricing'])['rules']),
        current = rows(workspace['rates'])
            .where((x) => x['is_active'] != false)
            .toList();
    return col([
      title(
          'Rates & Fees',
          'Manage product pricing, item rates, deposits, and quotes.',
          Wrap(spacing: 5, children: [
            OutlinedButton(
                onPressed: () => quote(products),
                child: const Text('Preview quote')),
            FilledButton(
                onPressed: () => editPricing(pricing),
                child: const Text('Pricing settings'))
          ])),
      metrics([
        M('Products', products.length.toString(), 'Rate sheet', Icons.sell,
            Clr.blue),
        M(
            'Service hours',
            s(rules['opens_at'] ?? '08:00') +
                '–' +
                s(rules['closes_at'] ?? '20:00'),
            'Daily',
            Icons.access_time,
            Clr.green),
        M('Equipment rates', current.length.toString(), 'Active rates',
            Icons.payments, Clr.purple)
      ]),
      panel(
          'Client rate sheet',
          'Deposits remain separate.',
          Column(children: [
            for (final p in products)
              card(Column(children: [
                Text(s(p['name']),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                for (final r in rows(p['rate_options']))
                  rowData(s(r['label']), money(r['amount'])),
                rowData('Deposit', money(p['deposit_amount'])),
                rowData('Overtime/hour', money(p['overtime_rate_per_hour']))
              ]))
          ])),
      panel(
          'Equipment rates',
          'Old rates remain in history.',
          Column(children: [
            Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                    onPressed: editRate, child: const Text('Update rate'))),
            for (final x in current)
              ListTile(
                  title: Text(s(x['item_name'])),
                  subtitle: Text(label(x['rate_type']) +
                      ' · ' +
                      date(x['effective_from'])),
                  trailing: Text(money(x['rental_rate'])))
          ]))
    ]);
  }

  Future<void> editRate() async {
    final active = items.where((x) => x['is_active'] != false).toList();
    if (active.isEmpty) return toast('Add equipment first.');
    final v = await form('Update equipment rate', [
      Field('itemId', 'Equipment', options: {
        for (final x in active)
          s(x['id']): s(x['name']) + ' · ' + s(x['item_code'])
      }),
      const Field('rateType', 'Rate basis',
          initial: 'HOURLY',
          options: {'HOURLY': 'Hourly', 'DAILY': 'Daily', 'FLAT': 'Flat'}),
      const Field('rentalRate', 'Rate', numeric: true),
      const Field('deposit', 'Deposit', initial: '0', numeric: true),
      const Field('latePenalty', 'Late penalty', initial: '0', numeric: true)
    ]);
    if (v == null) return;
    await mutate(() async {
      await api.post('/rates', body: {
        'itemId': v['itemId'],
        'rateType': v['rateType'],
        'rentalRate': n(v['rentalRate']),
        'deposit': n(v['deposit']),
        'latePenalty': n(v['latePenalty'])
      });
      await widget.onChanged();
      await widget.onInventoryRefresh();
    }, ok: 'Equipment rate saved.');
  }

  Future<void> editPricing(Map<String, dynamic> p) async {
    final rules = map(p['rules']),
        ps = rows(p['products']),
        fs = <Field>[
          Field('open', 'Opening time',
              initial: s(rules['opens_at'] ?? '08:00')),
          Field('close', 'Closing time',
              initial: s(rules['closes_at'] ?? '20:00')),
          Field('id', 'ID requirement',
              initial: rules['valid_id_required'] == false ? 'false' : 'true',
              options: const {'true': 'Required', 'false': 'No'}),
          Field('depositRequired', 'High value deposit',
              initial: rules['high_value_deposit_required'] == false
                  ? 'false'
                  : 'true',
              options: const {'true': 'Required', 'false': 'No'}),
          Field('lost', 'Lost piece fee',
              initial: s(rules['lost_piece_fee'] ?? 50), numeric: true)
        ];
    for (final x in ps) {
      final id = s(x['id']);
      fs.add(Field('dep_' + id, s(x['name']) + ' deposit',
          initial: s(x['deposit_amount'] ?? 0), numeric: true));
      fs.add(Field('ot_' + id, s(x['name']) + ' overtime',
          initial: s(x['overtime_rate_per_hour'] ?? 0), numeric: true));
      for (final r in rows(x['rate_options']))
        fs.add(Field(
            'rate_' + id + '_' + s(r['id']), s(x['name']) + ' ' + s(r['label']),
            initial: s(r['amount']), numeric: true));
    }
    final v = await form('Pricing settings', fs);
    if (v == null) return;
    final next = Map<String, dynamic>.from(p);
    next['rules'] = Map<String, dynamic>.from(rules)
      ..['opens_at'] = v['open']
      ..['closes_at'] = v['close']
      ..['valid_id_required'] = v['id'] == 'true'
      ..['high_value_deposit_required'] = v['depositRequired'] == 'true'
      ..['lost_piece_fee'] = n(v['lost']);
    next['products'] = ps.map((x) {
      final id = s(x['id']), item = Map<String, dynamic>.from(x);
      item['deposit_amount'] = n(v['dep_' + id]);
      item['overtime_rate_per_hour'] = n(v['ot_' + id]);
      item['rate_options'] = rows(x['rate_options']).map((r) {
        final y = Map<String, dynamic>.from(r);
        y['amount'] = n(v['rate_' + id + '_' + s(r['id'])]);
        return y;
      }).toList();
      return item;
    }).toList();
    await mutate(() async {
      await api.put('/pricing', body: next);
      await widget.onChanged();
    }, ok: 'Pricing saved.');
  }

  Future<void> quote(List<Map<String, dynamic>> ps) async {
    if (ps.isEmpty) return toast('No products loaded.');
    final v = await form('Preview rental quote', [
      Field('productId', 'Product',
          options: {for (final x in ps) s(x['id']): s(x['name'])}),
      const Field('durationMinutes', 'Minutes', initial: '60', numeric: true),
      const Field('mode', 'Mode',
          initial: 'TIMED',
          options: {'TIMED': 'Timed', 'WHOLE_STAY': 'Whole stay'})
    ]);
    if (v == null) return;
    await mutate(() async {
      final q = map((await api.post('/pricing/quote', body: {
        'productId': v['productId'],
        'durationMinutes': i(v['durationMinutes']),
        'mode': v['mode'],
        'startAt': DateTime.now().toUtc().toIso8601String()
      }))['quote']);
      if (mounted)
        await showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
                    title: Text(s(q['product_name']) + ' · ' + s(q['rate_label'])),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      rowData('Fee', money(q['rental_fee'])),
                      rowData('Overtime', money(q['overtime_fee'])),
                      rowData('Charges', money(q['rental_charge_total'])),
                      rowData('Deposit', money(q['deposit_amount'])),
                      rowData('Collect now', money(q['total_to_collect'])),
                      rowData('Due', date(q['due_at']))
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('Close'))
                    ]));
    }, ok: 'Quote ready.');
  }

  Widget reports() {
    final since = DateTime.now().subtract(const Duration(days: 30)),
        recent = rentals.where((x) {
          final d = dt(x['confirmed_rental_at'] ?? x['created_at']);
          return ['ACTIVE', 'COMPLETED'].contains(x['status']) &&
              d != null &&
              d.isAfter(since);
        }).toList(),
        returned = recent.where(isReturned).toList(),
        late = returned.where(isLate).length;
    final hrs = returned
            .map((x) {
              final a = dt(x['confirmed_rental_at']),
                  b = dt(x['confirmed_return_at']);
              return a == null || b == null
                  ? null
                  : b.difference(a).inMinutes / 60;
            })
            .whereType<double>()
            .toList(),
        avg = hrs.isEmpty
            ? '—'
            : hrs.reduce((a, b) => a + b).toStringAsFixed(1) + ' hrs';
    final repeat = <String, int>{};
    for (final x in recent) {
      final id = s(x['customer_id']);
      if (id.isNotEmpty) repeat.update(id, (a) => a + 1, ifAbsent: () => 1);
    }
    return col([
      title(
          'Reports',
          'Confirmed activity from the last 30 days.',
          OutlinedButton(
              onPressed: () => copyCsv(recent),
              child: const Text('Copy report CSV'))),
      metrics([
        M('Rental fees', money(sum(recent.map((x) => x['rental_fee']))),
            'Deposits excluded', Icons.payments, Clr.purple),
        M('Rentals', recent.length.toString(), 'Confirmed', Icons.receipt,
            Clr.blue),
        M(
            'Late returns',
            returned.isEmpty
                ? '—'
                : (late / returned.length * 100).toStringAsFixed(1) + '%',
            'Completed',
            Icons.schedule,
            Clr.amber),
        M('Avg duration', avg, 'Known times', Icons.timer, Clr.green)
      ]),
      panel('Equipment performance', 'Rental count and recorded fees.',
          performance(recent)),
      panel(
          'Operations',
          'Other workspace metrics.',
          Column(children: [
            rowData(
                'Repeat customers', repeat.values.where((x) => x > 1).length),
            rowData('Maintenance', rows(workspace['maintenance']).length),
            rowData('Verification attempts', checks.length),
            rowData('Pending requests', pendingRequests(null).length)
          ]))
    ]);
  }

  Widget performance(List<Map<String, dynamic>> data) {
    final counts = <String, int>{}, fees = <String, double>{};
    for (final x in data) {
      final k = s(x['item_name']).isEmpty ? 'Unknown item' : s(x['item_name']);
      counts.update(k, (a) => a + 1, ifAbsent: () => 1);
      fees.update(k, (a) => a + n(x['rental_fee']),
          ifAbsent: () => n(x['rental_fee']));
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.isEmpty
        ? empty('No confirmed rentals',
            'Performance appears as rentals are confirmed.')
        : Column(children: [
            for (final x in sorted.take(12))
              ListTile(
                  title: Text(x.key),
                  subtitle: LinearProgressIndicator(
                      value: x.value / sorted.first.value, color: Clr.orange),
                  trailing:
                      Text(x.value.toString() + ' · ' + money(fees[x.key])))
          ]);
  }

  Widget settings() {
    final b = map(workspace['settings']), users = rows(workspace['users']);
    return col([
      title('Settings',
          'Manage shared business details and administrator access.'),
      panel(
          'Business profile',
          'Shared business details and rental defaults.',
          Column(children: [
            rowData('Business name', b['business_name'] ?? 'Rent & Play'),
            rowData('Location', b['location'] ?? 'Los Baños, Laguna'),
            rowData('Currency', b['currency'] ?? 'PHP'),
            rowData('Timezone', b['timezone'] ?? 'Asia/Manila'),
            rowData('Grace hours', b['default_late_grace_hours'] ?? 0),
            TextButton.icon(
                onPressed: () => editBusiness(b),
                icon: const Icon(Icons.edit),
                label: const Text('Edit business'))
          ])),
      panel(
          'Admin accounts',
          'Only active ADMIN accounts can access the workspace.',
          Column(children: [
            Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                    onPressed: addAdmin,
                    icon: const Icon(Icons.person_add),
                    label: const Text('Add admin'))),
            for (final x in users)
              ListTile(
                  title: Text(s(x['full_name'] ?? x['name'])),
                  subtitle: Text(s(x['email']) + ' · ' + s(x['role'])),
                  trailing: PopupMenuButton<String>(
                      onSelected: (_) => toggleAdmin(x),
                      itemBuilder: (_) => [
                            PopupMenuItem(
                                value: 'toggle',
                                child: Text(x['is_active'] == false
                                    ? 'Activate'
                                    : 'Deactivate'))
                          ]))
          ])),
      panel(
          'Session',
          'Admin session is held in memory on this device.',
          OutlinedButton.icon(
              onPressed: widget.onSignOut,
              icon: const Icon(Icons.logout),
              label: const Text('Sign out')))
    ]);
  }

  Future<void> editBusiness(Map<String, dynamic> b) async {
    final v = await form('Business settings', [
      Field('businessName', 'Business name',
          initial: s(b['business_name'] ?? 'Rent & Play')),
      Field('location', 'Location',
          initial: s(b['location'] ?? 'Los Baños, Laguna')),
      Field('currency', 'Currency', initial: s(b['currency'] ?? 'PHP')),
      Field('timezone', 'Timezone', initial: s(b['timezone'] ?? 'Asia/Manila')),
      Field('defaultLateGraceHours', 'Late grace hours',
          initial: s(b['default_late_grace_hours'] ?? 0), numeric: true)
    ]);
    if (v == null) return;
    await mutate(() async {
      await api.patch('/settings', body: {
        'businessName': v['businessName'],
        'location': v['location'],
        'currency': v['currency'],
        'timezone': v['timezone'],
        'defaultLateGraceHours': n(v['defaultLateGraceHours'])
      });
      await widget.onChanged();
    }, ok: 'Business settings saved.');
  }

  Future<void> addAdmin() async {
    final v = await form('Add administrator', [
      const Field('fullName', 'Full name'),
      const Field('email', 'Email', email: true),
      const Field('password', 'Temp password (12+ chars)', obscure: true)
    ]);
    if (v == null) return;
    await mutate(() async {
      await api.post('/users', body: {
        'fullName': v['fullName'],
        'email': v['email'],
        'password': v['password'],
        'role': 'ADMIN'
      });
      await widget.onChanged();
    }, ok: 'Administrator added.');
  }

  Future<void> toggleAdmin(Map<String, dynamic> x) async {
    final enable = x['is_active'] == false;
    await mutate(() async {
      await api.patch('/users/' + s(x['id']),
          body: {'role': 'ADMIN', 'isActive': enable});
      await widget.onChanged();
    }, ok: enable ? 'Administrator activated.' : 'Administrator deactivated.');
  }

  Widget adminSettings() {
    final u = map(api.currentUser);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final active = u['is_active'] != false;
    return col([
      title(
        'Admin settings',
        'Manage your administrator account, appearance, and sign-in security.',
      ),
      panel(
        'Administrator account',
        'Your changes apply to this admin account only.',
        Column(children: [
          rowData('Full name', u['name'] ?? u['full_name']),
          rowData('Email', u['email']),
          rowData('Access role', 'Administrator'),
          rowData('Account status', active ? 'Active' : 'Inactive'),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: editProfile,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit admin account'),
            ),
          ),
        ]),
      ),
      panel(
        'Appearance',
        'Choose how the admin workspace looks on this device.',
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: Icon(
            themeProvider.isDarkMode ? Icons.dark_mode : Icons.light_mode,
            color: Clr.orange,
          ),
          title: const Text('Dark mode'),
          subtitle: Text(themeProvider.isDarkMode
              ? 'Dark theme is enabled.'
              : 'Light theme is enabled.'),
          value: themeProvider.isDarkMode,
          onChanged: themeProvider.toggleTheme,
        ),
      ),
      panel(
        'Account security',
        'Send a secure password reset link to your admin email.',
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: resetPassword,
            icon: const Icon(Icons.mark_email_read_outlined),
            label: const Text('Send password reset email'),
          ),
        ),
      ),
    ]);
  }

  Widget profile() {
    final u = map(api.currentUser);
    return col([
      title('Admin profile', 'Signed-in administrator details.'),
      panel(
          'Account profile',
          'From the admin service.',
          Column(children: [
            rowData('Name', u['name'] ?? u['full_name']),
            rowData('Email', u['email']),
            rowData('Role', u['role'] ?? 'ADMIN'),
            TextButton.icon(
                onPressed: editProfile,
                icon: const Icon(Icons.edit),
                label: const Text('Edit profile'))
          ]))
    ]);
  }

  Future<void> editProfile() async {
    final u = map(api.currentUser),
        v = await form('Edit profile', [
          Field('fullName', 'Full name',
              initial: s(u['name'] ?? u['full_name'])),
          Field('email', 'Email', initial: s(u['email']), email: true)
        ]);
    if (v == null) return;
    await mutate(() async {
      await api.patch('/profile',
          body: {'fullName': v['fullName'], 'email': v['email']});
      await widget.onChanged();
    }, ok: 'Profile updated.');
  }

  Future<void> resetPassword() async {
    final email = s(map(api.currentUser)['email']);
    if (email.isEmpty) return toast('Signed-in email unavailable.');
    await mutate(() async {
      await api.post('/auth/password-reset', body: {'email': email});
    }, ok: 'If this account exists, a reset email was sent.');
  }

  Future<void> showQr(Map<String, dynamic> x) async {
    final code = s(x['qrCode']).isNotEmpty
        ? s(x['qrCode'])
        : (s(x['code']).isNotEmpty
            ? s(x['code'])
            : (s(x['qr_code']).isNotEmpty ? s(x['qr_code']) : s(x['id'])));
    final name = s(x['name']).isNotEmpty
        ? s(x['name'])
        : (s(x['itemName']).isNotEmpty ? s(x['itemName']) : s(x['item_name']));
    final customer = s(x['customerName']).isNotEmpty ? s(x['customerName']) : s(x['customer_name']);

    EquipmentQrLabelDialog.show(
      context,
      qrCode: code.isNotEmpty ? code : 'SPORT-EQUIP-001',
      itemName: name.isNotEmpty ? name : 'Equipment Item',
      customerName: customer.isNotEmpty ? customer : null,
      rentalId: s(x['rentalId']).isNotEmpty ? s(x['rentalId']) : null,
    );
  }

  Future<void> copyCsv(List<Map<String, dynamic>> data) async {
    final matrix = <List<dynamic>>[
      [
        'Rental ID',
        'Equipment',
        'Item code',
        'Customer',
        'Status',
        'Rented',
        'Due',
        'Returned',
        'Fee',
        'Deposit'
      ],
      for (final x in data)
        [
          x['rental_code'] ?? x['id'],
          x['item_name'],
          x['item_code'],
          x['customer_name'],
          rentalStatus(x),
          x['confirmed_rental_at'] ?? x['created_at'],
          x['due_at'],
          x['confirmed_return_at'],
          x['rental_fee'],
          x['deposit_amount']
        ]
    ];
    await Clipboard.setData(ClipboardData(
        text: matrix
            .map((r) =>
                r.map((x) => '"' + s(x).replaceAll('"', '""') + '"').join(','))
            .join('\r\n')));
    toast('CSV copied to clipboard.');
  }

  Future<Map<String, String>?> form(String t, List<Field> f) =>
      showDialog<Map<String, String>>(
          context: context, builder: (c) => QuickForm(t, f));
  Future<void> mutate(Future<void> Function() task,
      {required String ok}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await task();
      if (mounted) toast(ok);
    } on AdminApiException catch (e) {
      if (mounted) toast(e.message);
    } catch (e) {
      if (mounted) toast('Admin action failed: ' + e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget col(List<Widget> x) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: x);
  Widget title(String t, String sub, [Widget? a]) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(builder: (c, b) {
        final h =
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t,
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w900, color: Clr.ink)),
          Text(sub, style: const TextStyle(color: Clr.muted))
        ]);
        if (a == null) return h;
        if (b.maxWidth < 560)
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [h, const SizedBox(height: 8), a]);
        return Row(children: [Expanded(child: h), a]);
      }));
  Widget panel(String t, String sub, Widget child, {Widget? trailing}) =>
      Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Clr.line),
              borderRadius: BorderRadius.circular(17)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(t,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Clr.ink,
                            fontSize: 16)),
                    Text(sub,
                        style: const TextStyle(color: Clr.muted, fontSize: 11))
                  ])),
              if (trailing != null) trailing
            ]),
            const SizedBox(height: 10),
            child
          ]));
  Widget card(Widget x) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131D2D) : Colors.white,
          border: Border.all(color: isDark ? const Color(0xFF1E2C42) : Clr.line),
          borderRadius: BorderRadius.circular(14)),
      child: x);
  }
  Widget metrics(List<M> x) => LayoutBuilder(builder: (c, b) {
        final n = b.maxWidth >= 900
                ? 4
                : b.maxWidth >= 540
                    ? 2
                    : b.maxWidth >= 340
                        ? 2
                        : 1,
            w = (b.maxWidth - 8 * (n - 1)) / n;
        return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in x) SizedBox(width: w, child: MetricCard(a))
            ]));
      });
  Widget search(String h) => TextField(
      onChanged: (v) => setState(() => query = v),
      decoration: InputDecoration(
          hintText: h,
          prefixIcon: const Icon(Icons.search, size: 20),
          filled: true,
          fillColor: Clr.canvas,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none)));
  Widget chips(List<String> x) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final v in x)
          Padding(
              padding: const EdgeInsets.only(right: 5),
              child: ChoiceChip(
                  label: Text(label(v)),
                  selected: filter == v,
                  onSelected: (_) => setState(() => filter = v)))
      ]));
  Widget empty(String t, String s) => Padding(
      padding: const EdgeInsets.all(18),
      child: Column(children: [
        const Icon(Icons.inbox_outlined, color: Clr.muted, size: 30),
        Text(t, style: const TextStyle(fontWeight: FontWeight.w800)),
        Text(s,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Clr.muted, fontSize: 12))
      ]));
  Widget badge(String x) {
    final c = status(x.toUpperCase());
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: c.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(20)),
        child: Text(x,
            style: TextStyle(
                color: c, fontSize: 10, fontWeight: FontWeight.w800)));
  }

  Widget itemIcon(String x) {
    final q = x.toLowerCase(),
        icon = q.contains('bike')
            ? Icons.pedal_bike
            : q.contains('ball')
                ? Icons.sports_basketball
                : q.contains('game')
                    ? Icons.sports_esports
                    : Icons.inventory_2;
    return Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
            color: const Color(0xFFFFF0E4),
            borderRadius: BorderRadius.circular(11)),
        child: Icon(icon, color: Clr.orange));
  }

  Widget fact(String a, String b) => RichText(
          text: TextSpan(
              style: const TextStyle(fontSize: 11, color: Clr.muted),
              children: [
            TextSpan(text: a + ' '),
            TextSpan(
                text: b,
                style: const TextStyle(
                    color: Clr.ink, fontWeight: FontWeight.w700))
          ]));
  Widget rowData(String a, dynamic b) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
            child: Text(a,
                style: const TextStyle(fontSize: 12, color: Clr.muted))),
        Flexible(
            child: Text(s(b).isEmpty ? '—' : s(b),
                textAlign: TextAlign.end,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))
      ]));
  String money(dynamic x) => '₱' + n(x).toStringAsFixed(2);
  String label(dynamic x) => s(x)
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) =>
          w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
  Color status(String x) => x.contains('OVERDUE') || x.contains('REJECTED')
      ? Clr.red
      : x.contains('PENDING') ||
              x.contains('DUE') ||
              x.contains('MAINTENANCE') ||
              x.contains('AWAITING')
          ? Clr.amber
          : x.contains('AVAILABLE') ||
                  x.contains('RETURNED') ||
                  x.contains('CONFIRMED') ||
                  x.contains('COMPLETED')
              ? Clr.green
              : Clr.blue;
  String rentalStatus(Map<String, dynamic> x) {
    if (x['status'] == 'PENDING_VERIFICATION') return 'Awaiting confirmation';
    if (isReturned(x)) return isLate(x) ? 'Returned late' : 'Returned';
    if (x['status'] == 'ACTIVE') {
      final d = dt(x['due_at']);
      if (d != null && d.isBefore(DateTime.now())) return 'Overdue';
      if (d != null && key(d) == key(DateTime.now())) return 'Due today';
    }
    return label(x['status']);
  }

  bool isReturned(Map<String, dynamic> x) =>
      x['confirmed_return_at'] != null || x['status'] == 'COMPLETED';
  bool isLate(Map<String, dynamic> x) {
    final a = dt(x['due_at']), b = dt(x['confirmed_return_at']);
    return a != null && b != null && b.isAfter(a);
  }

  DateTime? dt(dynamic x) =>
      x is DateTime ? x : DateTime.tryParse(s(x).replaceFirst(' ', 'T'));
  String date(dynamic x) {
    final d = dt(x)?.toLocal();
    return d == null
        ? '—'
        : d.year.toString() +
            '-' +
            d.month.toString().padLeft(2, '0') +
            '-' +
            d.day.toString().padLeft(2, '0') +
            ' ' +
            d.hour.toString().padLeft(2, '0') +
            ':' +
            d.minute.toString().padLeft(2, '0');
  }

  String key(DateTime d) =>
      d.year.toString() +
      '-' +
      d.month.toString().padLeft(2, '0') +
      '-' +
      d.day.toString().padLeft(2, '0');
  double sum(Iterable<dynamic> x) => x.fold<double>(0, (a, b) => a + n(b));
  String initials(String x) {
    final p =
        x.trim().split(RegExp(r'\s+')).where((a) => a.isNotEmpty).toList();
    return p.isEmpty ? 'A' : p.take(2).map((a) => a[0].toUpperCase()).join();
  }

  void toast(String x) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(x)));
  }
}

class Clr {
  static const canvas = Color(0xFFF6F8FB),
      line = Color(0xFFE7ECF2),
      ink = Color(0xFF17263A),
      muted = Color(0xFF758397),
      navy = Color(0xFF173451),
      orange = Color(0xFFF18739),
      blue = Color(0xFF3578C8),
      green = Color(0xFF288A62),
      purple = Color(0xFF7A62B5),
      amber = Color(0xFFC37A17),
      red = Color(0xFFBF4A4A);
}

class M {
  const M(this.title, this.value, this.note, this.icon, this.color);
  final String title, value, note;
  final IconData icon;
  final Color color;
}

class MetricCard extends StatelessWidget {
  const MetricCard(this.x);
  final M x;
  @override
  Widget build(BuildContext c) {
    final isDark = Theme.of(c).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131D2D) : Colors.white,
          border: Border.all(color: isDark ? const Color(0xFF1E2C42) : Clr.line),
          borderRadius: BorderRadius.circular(15)),
      child: Row(children: [
        Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: x.color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(x.icon, color: x.color, size: 19)),
        const SizedBox(width: 8),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(x.title, style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF94A3B8) : Clr.muted)),
          Text(x.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900, color: isDark ? const Color(0xFFF8FAFC) : Clr.ink)),
          Text(x.note,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: isDark ? const Color(0xFF94A3B8) : Clr.muted))
        ]))
      ]));
  }
}

class BarChart extends CustomPainter {
  const BarChart(this.a);
  final List<double> a;
  @override
  void paint(Canvas c, Size s) {
    final g = Paint()..color = Clr.line;
    for (var j = 0; j < 4; j++) {
      final y = s.height * j / 3;
      c.drawLine(Offset(0, y), Offset(s.width, y), g);
    }
    if (a.isEmpty) return;
    final max = a.fold<double>(0, (x, y) => x > y ? x : y),
        gap = 7.0,
        w = (s.width - gap * (a.length - 1)) / a.length,
        p = Paint()..color = Clr.orange;
    for (var j = 0; j < a.length; j++) {
      final h = max == 0 ? 3.0 : (s.height - 5) * a[j] / max;
      c.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(
                  j * (w + gap), s.height - h, w, h.clamp(3.0, s.height)),
              const Radius.circular(5)),
          p);
    }
  }

  @override
  bool shouldRepaint(covariant BarChart o) => o.a != a;
}

class Qr extends CustomPainter {
  const Qr(this.n, this.bits);
  final int n;
  final List<int> bits;
  @override
  void paint(Canvas c, Size s) {
    if (n <= 0 || bits.length != n * n) return;
    final w = s.shortestSide / n,
        ox = (s.width - w * n) / 2,
        oy = (s.height - w * n) / 2;
    c.drawRect(Offset.zero & s, Paint()..color = Colors.white);
    final p = Paint()..color = Colors.black;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (bits[y * n + x] > 0)
          c.drawRect(Rect.fromLTWH(ox + x * w, oy + y * w, w + .2, w + .2), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant Qr o) => o.n != n || o.bits != bits;
}

class Field {
  const Field(this.name, this.label,
      {this.initial = '',
      this.optional = false,
      this.numeric = false,
      this.email = false,
      this.obscure = false,
      this.multiline = false,
      this.options = const {}});
  final String name, label, initial;
  final bool optional, numeric, email, obscure, multiline;
  final Map<String, String> options;
}

class QuickForm extends StatefulWidget {
  const QuickForm(this.title, this.fields);
  final String title;
  final List<Field> fields;
  @override
  State<QuickForm> createState() => _QuickFormState();
}

class _QuickFormState extends State<QuickForm> {
  final key = GlobalKey<FormState>();
  final text = <String, TextEditingController>{};
  final selected = <String, String>{};
  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      if (f.options.isEmpty) {
        text[f.name] = TextEditingController(text: f.initial);
      } else {
        selected[f.name] =
            f.options.containsKey(f.initial) ? f.initial : f.options.keys.first;
      }
    }
  }

  @override
  void dispose() {
    for (final c in text.values) {
      c.dispose();
    }
    super.dispose();
  }

  void submit() {
    if (!key.currentState!.validate()) return;
    final v = <String, String>{...selected};
    for (final x in text.entries) {
      v[x.key] = x.value.text.trim();
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext c) => AlertDialog(
          title: Text(widget.title),
          content: SizedBox(
              width: 500,
              height: MediaQuery.sizeOf(c).height * .75,
              child: Form(
                  key: key,
                  child: ListView(children: [
                    for (final f in widget.fields)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 11),
                          child: f.options.isNotEmpty
                              ? DropdownButtonFormField<String>(
                                  initialValue: selected[f.name],
                                  decoration: InputDecoration(
                                      labelText: f.label,
                                      border: const OutlineInputBorder()),
                                  items: [
                                    for (final x in f.options.entries)
                                      DropdownMenuItem(
                                          value: x.key,
                                          child: Text(x.value,
                                              overflow: TextOverflow.ellipsis))
                                  ],
                                  onChanged: (x) {
                                    if (x != null)
                                      setState(() => selected[f.name] = x);
                                  },
                                  validator: (x) => !f.optional &&
                                          (x == null || x.isEmpty)
                                      ? 'Choose ' + f.label.toLowerCase() + '.'
                                      : null)
                              : TextFormField(
                                  controller: text[f.name],
                                  obscureText: f.obscure,
                                  keyboardType: f.numeric
                                      ? const TextInputType.numberWithOptions(
                                          decimal: true)
                                      : f.email
                                          ? TextInputType.emailAddress
                                          : f.multiline
                                              ? TextInputType.multiline
                                              : TextInputType.text,
                                  minLines: f.multiline ? 3 : 1,
                                  maxLines: f.multiline ? 5 : 1,
                                  decoration: InputDecoration(
                                      labelText: f.label,
                                      border: const OutlineInputBorder()),
                                  validator: (x) {
                                    final v = (x ?? '').trim();
                                    if (!f.optional && v.isEmpty)
                                      return 'Enter ' +
                                          f.label.toLowerCase() +
                                          '.';
                                    if (f.email &&
                                        v.isNotEmpty &&
                                        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                            .hasMatch(v))
                                      return 'Enter a valid email.';
                                    if (f.numeric &&
                                        v.isNotEmpty &&
                                        double.tryParse(v) == null)
                                      return 'Enter a valid number.';
                                    if (f.name == 'password' && v.length < 12)
                                      return 'Use at least 12 characters.';
                                    return null;
                                  }))
                  ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(onPressed: submit, child: const Text('Save'))
          ]);
}
