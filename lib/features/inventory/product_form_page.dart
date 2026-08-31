import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'data/product_repository.dart';
import 'models/product.dart';

/// Add / edit a product. Refills use the standard size list
/// (3, 6, 13, 22.5, 35, 45, 50 kg); cylinders share the same sizes;
/// accessories & services have no size.
class ProductFormPage extends StatefulWidget {
  const ProductFormPage({super.key, this.product});

  final Product? product;

  @override
  State<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends State<ProductFormPage> {
  final _repo = ProductRepository();
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _saleCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _thresholdCtrl = TextEditingController();

  ProductType _type = ProductType.refill;
  double? _sizeKg;
  bool _saving = false;
  String? _saveError;

  bool get _isEditing => widget.product != null;
  bool get _hasSize =>
      _type == ProductType.refill || _type == ProductType.cylinder;
  bool get _isBelowCost {
    final sale = double.tryParse(_saleCtrl.text.trim());
    final cost = double.tryParse(_costCtrl.text.trim());
    return sale != null && cost != null && sale < cost;
  }

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p != null) {
      _nameCtrl.text = p.name;
      _brandCtrl.text = p.brand ?? '';
      _saleCtrl.text = p.salePrice.toStringAsFixed(0);
      _costCtrl.text = p.costPrice.toStringAsFixed(0);
      _thresholdCtrl.text = p.lowStockThreshold.toString();
      _type = p.productType;
      _sizeKg = p.sizeKg;
    } else {
      _thresholdCtrl.text = '5';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _brandCtrl.dispose();
    _saleCtrl.dispose();
    _costCtrl.dispose();
    _thresholdCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      await _repo.saveProduct(
        productId: widget.product?.id,
        name: _nameCtrl.text.trim(),
        productType: _type,
        sizeKg: _hasSize ? _sizeKg : null,
        brand: _brandCtrl.text.trim().isEmpty ? null : _brandCtrl.text.trim(),
        salePrice: double.parse(_saleCtrl.text.trim()),
        costPrice: double.parse(_costCtrl.text.trim()),
        lowStockThreshold: int.tryParse(_thresholdCtrl.text.trim()) ?? 5,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit product' : 'New product')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    DropdownButtonFormField<ProductType>(
                      initialValue: _type,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Product type *',
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                      items: [
                        for (final type in ProductType.values)
                          DropdownMenuItem(
                            value: type,
                            child: Row(
                              children: [
                                Icon(type.icon, size: 18),
                                const SizedBox(width: 8),
                                Text(type.label),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        _type = v ?? ProductType.refill;
                        _sizeKg = null;
                      }),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Product name *',
                        hintText: 'e.g. Refill 13kg',
                        prefixIcon: Icon(Icons.local_fire_department_outlined),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter the product name'
                          : null,
                    ),
                    if (_hasSize) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<double>(
                        initialValue: _sizeKg,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Size *',
                          prefixIcon: Icon(Icons.straighten_outlined),
                        ),
                        hint: const Text('Select size'),
                        items: [
                          for (final size in Product.refillSizes)
                            DropdownMenuItem(
                              value: size,
                              child: Text(Product.formatSizeKg(size)),
                            ),
                        ],
                        onChanged: (v) => setState(() => _sizeKg = v),
                        validator: (v) => v == null ? 'Select a size' : null,
                      ),
                    ],
                    if (_type == ProductType.refill ||
                        _type == ProductType.cylinder) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _brandCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Brand (optional)',
                          hintText: 'e.g. Gateway, Total, K-Gas',
                          prefixIcon: Icon(Icons.local_gas_station_outlined),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _saleCtrl,
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Selling price KSh *',
                        prefixIcon: Icon(Icons.sell_outlined),
                      ),
                      validator: (v) {
                        final value = double.tryParse((v ?? '').trim());
                        if (value == null || value <= 0) {
                          return 'Enter a valid selling price';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _costCtrl,
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Buying cost KSh *',
                        hintText: 'Updated by purchases',
                        prefixIcon: Icon(Icons.shopping_basket_outlined),
                      ),
                      validator: (v) {
                        final value = double.tryParse((v ?? '').trim());
                        if (value == null || value < 0) {
                          return 'Enter a valid buying cost';
                        }
                        return null;
                      },
                    ),
                    if (_isBelowCost) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.warning_amber_outlined,
                              size: 18,
                              color: AppColors.warning,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Selling below cost',
                                style: TextStyle(
                                  color: AppColors.warning,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _thresholdCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Low stock alert at (units)',
                        prefixIcon: Icon(Icons.priority_high_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_saveError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _saveError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_isEditing ? 'Save changes' : 'Save product'),
            ),
          ],
        ),
      ),
    );
  }
}
