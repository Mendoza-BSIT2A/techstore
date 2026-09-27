import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/dummy_product.dart';
import '../models/product.dart';
import '../services/api_exception.dart';
import '../services/app_services.dart';
import '../widgets/dummyjson_product_picker.dart';
import '../widgets/product_image.dart';
import '../widgets/state_views.dart';

/// Create (POST) or edit (PUT) a product.
///
/// Pass [product] to edit it; its values pre-populate the form. Otherwise the
/// form creates a new product, optionally pre-filled from a DummyJSON product.
/// Pops with the saved [Product] on success.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({
    super.key,
    this.product,
    this.prefill,
    this.prefillImageUrl,
  });

  final Product? product;

  /// DummyJSON product whose details pre-fill a new product (ignored when editing).
  final DummyProduct? prefill;

  /// Photo to use instead of the [prefill] product's thumbnail.
  final String? prefillImageUrl;

  bool get isEditing => product != null;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  // Same limits as the server-side validation.
  static const _nameMax = 120;
  static const _brandMax = 60;
  static const _descriptionMax = 2000;
  static const _priceMessage =
      'Price must be a number from 0.01 to 1,000,000 with at most 2 decimals.';
  static const _stockMessage =
      'Stock must be a whole number from 0 to 100,000.';

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _brand;
  late final TextEditingController _price;
  late final TextEditingController _stock;
  late final TextEditingController _description;
  late final TextEditingController _imageUrl;

  String? _category;
  int? _dummyId;

  /// Title of the linked DummyJSON product, when known.
  String? _dummyTitle;

  late final Map<String, Object?> _initialValues;
  Map<String, String> _serverErrors = {};
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;
  bool _saving = false;
  bool _fetchingPhoto = false;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    final prefill = product == null ? widget.prefill : null;

    _name = TextEditingController(
      text: product?.name ?? _clip(prefill?.title, _nameMax),
    );
    _brand = TextEditingController(
      text: product?.brand ?? _clip(prefill?.brand, _brandMax),
    );
    _price = TextEditingController(
      text: product != null
          ? _priceText(product.price)
          : prefill != null && prefill.price > 0
          ? _priceText(prefill.price)
          : '',
    );
    _stock = TextEditingController(
      text: product != null
          ? '${product.stock}'
          : prefill == null
          ? ''
          : '${prefill.stock}',
    );
    _description = TextEditingController(
      text:
          product?.description ?? _clip(prefill?.description, _descriptionMax),
    );
    _imageUrl = TextEditingController(
      text: product != null
          ? product.imageUrl ?? ''
          : widget.prefillImageUrl ?? prefill?.coverImage ?? '',
    );
    _category = Product.categories.contains(product?.category)
        ? product!.category
        : prefill?.shopCategory;
    _dummyId = product?.dummyJsonId ?? prefill?.id;
    _dummyTitle = prefill?.title;
    _initialValues = _currentValues();
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _brand,
      _price,
      _stock,
      _description,
      _imageUrl,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, Object?> _currentValues() => {
    'name': _name.text.trim(),
    'category': _category,
    'brand': _brand.text.trim(),
    'price': _price.text.trim(),
    'stock': _stock.text.trim(),
    'description': _description.text.trim(),
    'image_url': _imageUrl.text.trim(),
    'dummyjson_id': _dummyId,
  };

  bool get _isDirty => !mapEquals(_currentValues(), _initialValues);

  static String _priceText(double price) => price.toStringAsFixed(2);

  /// Trims [text] to at most [max] code points (the server's mb_strlen).
  static String _clip(String? text, int max) {
    final value = text?.trim() ?? '';
    final runes = value.runes;
    return runes.length <= max
        ? value
        : String.fromCharCodes(runes.take(max)).trim();
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  /// Server-side (422) messages take priority so they show under the right field.
  String? _check(String field, String? Function() localRule) =>
      _serverErrors[field] ?? localRule();

  void _clearServerError(String field) {
    if (_serverErrors.containsKey(field)) {
      setState(() => _serverErrors = Map.of(_serverErrors)..remove(field));
    }
  }

  String? _validateName(String? value) => _check('name', () {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Please enter the product name.';
    // Count code points like the server (mb_strlen), so emoji count once.
    final length = name.runes.length;
    if (length < 2) return 'Name must be at least 2 characters.';
    if (length > _nameMax) return 'Name must be at most $_nameMax characters.';
    final existing = AppServices.productStore.byName(name);
    if (existing != null && existing.id != widget.product?.id) {
      return 'You already have a product with this name.';
    }
    return null;
  });

  String? _validatePrice(String? value) => _check('price', () {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Please enter a price.';
    final price = double.tryParse(text);
    if (price == null ||
        !RegExp(r'^\d*\.?\d{0,2}$').hasMatch(text) ||
        price < Product.minPrice ||
        price > Product.maxPrice) {
      return _priceMessage;
    }
    return null;
  });

  String? _validateStock(String? value) => _check('stock', () {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Please enter the stock quantity.';
    final stock = int.tryParse(text);
    if (stock == null || stock < 0 || stock > Product.maxStock) {
      return _stockMessage;
    }
    return null;
  });

  String? _validateImageUrl(String? value) => _check('image_url', () {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    // Same rule as the server: printable ASCII only (no spaces or accents).
    if (RegExp(r'[^!-~]').hasMatch(text)) {
      return 'Links cannot contain spaces or accented characters.';
    }
    final uri = Uri.tryParse(text);
    final valid =
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    if (!valid) return 'Enter a full link starting with http:// or https://';
    if (text.length > 500) return 'Link must be at most 500 characters.';
    return null;
  });

  String? Function(String?) _maxLength(String field, int max, String label) =>
      (value) => _check(field, () {
        final length = value?.trim().runes.length ?? 0;
        return length > max ? '$label must be at most $max characters.' : null;
      });

  // ---------------------------------------------------------------------------
  // DummyJSON helpers
  // ---------------------------------------------------------------------------

  Future<void> _pickDummyProduct() async {
    final picked = await showDummyJsonProductPicker(
      context,
      selectedId: _dummyId,
    );
    if (picked == null || !mounted) return;
    _applyDummyProduct(picked);
  }

  /// Links [dummy] and copies its details into the fields that are still
  /// empty, so nothing the user typed is overwritten.
  void _applyDummyProduct(DummyProduct dummy) {
    setState(() {
      _dummyId = dummy.id;
      _dummyTitle = dummy.title;
      _serverErrors = Map.of(_serverErrors)..remove('dummyjson_id');
      if (_name.text.trim().isEmpty) _name.text = _clip(dummy.title, _nameMax);
      _category ??= dummy.shopCategory;
      if (_brand.text.trim().isEmpty) {
        _brand.text = _clip(dummy.brand, _brandMax);
      }
      if (_price.text.trim().isEmpty && dummy.price > 0) {
        _price.text = _priceText(dummy.price);
      }
      if (_stock.text.trim().isEmpty) _stock.text = '${dummy.stock}';
      if (_description.text.trim().isEmpty) {
        _description.text = _clip(dummy.description, _descriptionMax);
      }
      if (_imageUrl.text.trim().isEmpty) {
        _imageUrl.text = dummy.coverImage ?? '';
      }
    });
  }

  void _unlinkDummyProduct() {
    setState(() {
      _dummyId = null;
      _dummyTitle = null;
      _serverErrors = Map.of(_serverErrors)..remove('dummyjson_id');
    });
  }

  /// Uses the next photo of the linked DummyJSON product, or opens the picker
  /// when no product is linked yet.
  Future<void> _importPhoto() async {
    final id = _dummyId;
    if (id == null) {
      await _pickDummyProduct();
      return;
    }
    setState(() => _fetchingPhoto = true);
    try {
      final dummy = await AppServices.dummyJson.product(id);
      if (!mounted) return;
      final photos = dummy.allImages;
      if (photos.isEmpty) {
        showAppSnackBar(context, 'This DummyJSON product has no photos.');
        return;
      }
      // Each tap moves on to the next photo of the product.
      final current = photos.indexOf(_imageUrl.text.trim());
      _imageUrl.text = photos[(current + 1) % photos.length];
      _dummyTitle = dummy.title;
      _clearServerError('image_url');
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _fetchingPhoto = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _serverErrors = {};
      _autovalidate = AutovalidateMode.onUserInteraction;
    });

    if (!_formKey.currentState!.validate()) {
      showAppSnackBar(
        context,
        'Please fix the highlighted fields.',
        isError: true,
      );
      return;
    }

    final product = Product(
      id: widget.product?.id,
      name: _name.text.trim(),
      category: _category!,
      brand: _brand.text.trim(),
      price: double.parse(_price.text.trim()),
      stock: int.parse(_stock.text.trim()),
      description: _description.text.trim(),
      imageUrl: _imageUrl.text.trim().isEmpty ? null : _imageUrl.text.trim(),
      dummyJsonId: _dummyId,
    );

    setState(() => _saving = true);
    try {
      final store = AppServices.productStore;
      final saved = widget.isEditing
          ? await store.update(product)
          : await store.create(product);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _serverErrors = Map.of(e.fieldErrors));
      _formKey.currentState!.validate();
      showAppSnackBar(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your unsaved changes will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.isEditing ? 'Edit Product' : 'Add Product';

    return PopScope(
      canPop: !_isDirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Form(
          key: _formKey,
          autovalidateMode: _autovalidate,
          onChanged: () => setState(() {}),
          // A Column (not a lazy ListView) keeps every field mounted, so
          // validate() always checks all of them, even when scrolled away.
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ImagePreview(
                      controller: _imageUrl,
                      busy: _fetchingPhoto,
                      onImport: _saving ? null : _importPhoto,
                    ),
                    const SizedBox(height: 20),
                    _SectionLabel('Product details'),
                    TextFormField(
                      key: const Key('field_name'),
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      maxLength: _nameMax,
                      decoration: const InputDecoration(
                        labelText: 'Product name *',
                        prefixIcon: Icon(Icons.devices),
                        counterText: '',
                      ),
                      validator: _validateName,
                      onChanged: (_) => _clearServerError('name'),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      key: const Key('field_category'),
                      initialValue: _category,
                      // Lets the selected text shrink on narrow screens with
                      // large fonts instead of overflowing.
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Category *',
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                      items: [
                        for (final category in Product.categories)
                          DropdownMenuItem(
                            value: category,
                            child: Text(
                              category,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      validator: (value) => _check(
                        'category',
                        () =>
                            value == null ? 'Please choose a category.' : null,
                      ),
                      onChanged: _saving
                          ? null
                          : (value) {
                              _category = value;
                              _clearServerError('category');
                            },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('field_brand'),
                      controller: _brand,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Brand',
                        hintText: 'Apple, Dell, Kingston…',
                        prefixIcon: Icon(Icons.sell_outlined),
                      ),
                      validator: _maxLength('brand', _brandMax, 'Brand'),
                      onChanged: (_) => _clearServerError('brand'),
                    ),
                    const SizedBox(height: 24),
                    _SectionLabel('Price & stock'),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const Key('field_price'),
                            controller: _price,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textInputAction: TextInputAction.next,
                            inputFormatters: [_PriceInputFormatter()],
                            decoration: const InputDecoration(
                              labelText: 'Price (USD) *',
                              errorMaxLines: 4,
                              prefixText: '\$ ',
                              hintText: '0.00',
                            ),
                            validator: _validatePrice,
                            onChanged: (_) => _clearServerError('price'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            key: const Key('field_stock'),
                            controller: _stock,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            maxLength: 6,
                            decoration: const InputDecoration(
                              labelText: 'Stock (units) *',
                              errorMaxLines: 4,
                              counterText: '',
                            ),
                            validator: _validateStock,
                            onChanged: (_) => _clearServerError('stock'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _SectionLabel('Description'),
                    TextFormField(
                      key: const Key('field_description'),
                      controller: _description,
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 3,
                      maxLines: 6,
                      maxLength: _descriptionMax,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        hintText: 'Specs, condition, what is in the box…',
                        alignLabelWithHint: true,
                      ),
                      validator: _maxLength(
                        'description',
                        _descriptionMax,
                        'Description',
                      ),
                      onChanged: (_) => _clearServerError('description'),
                    ),
                    const SizedBox(height: 16),
                    _SectionLabel('Photo & DummyJSON link'),
                    _DummyJsonLinkField(
                      dummyId: _dummyId,
                      title: _dummyTitle,
                      errorText: _serverErrors['dummyjson_id'],
                      onPick: _saving ? null : _pickDummyProduct,
                      onClear: _saving ? null : _unlinkDummyProduct,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('field_image_url'),
                      controller: _imageUrl,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: 'Image URL',
                        hintText: 'https://…',
                        prefixIcon: const Icon(Icons.link),
                        suffixIcon: _imageUrl.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _imageUrl.clear();
                                  _clearServerError('image_url');
                                  setState(() {});
                                },
                              ),
                      ),
                      validator: _validateImageUrl,
                      onChanged: (_) => _clearServerError('image_url'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '* Required',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              key: const Key('submit_product'),
              onPressed: _saving ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(widget.isEditing ? Icons.save_outlined : Icons.add),
              label: Text(
                _saving
                    ? 'Saving…'
                    : widget.isEditing
                    ? 'Save changes'
                    : 'Add product',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Accepts digits with at most one dot and two decimals ("1999.99").
/// An edit that would break the pattern is rejected, so the field keeps its
/// previous text. A decimal comma is turned into a dot.
class _PriceInputFormatter extends TextInputFormatter {
  static final _pattern = RegExp(r'^\d{0,7}(\.\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(',', '.');
    if (!_pattern.hasMatch(text)) return oldValue;
    return text == newValue.text ? newValue : newValue.copyWith(text: text);
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// Live preview of the image URL field.
class _ImagePreview extends StatelessWidget {
  const _ImagePreview({
    required this.controller,
    required this.busy,
    required this.onImport,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final text = value.text.trim();
        final uri = Uri.tryParse(text);
        final previewable = uri != null && uri.hasScheme && uri.host.isNotEmpty;
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ProductImage(
                  previewable ? text : null,
                  fit: BoxFit.contain,
                  backgroundColor: Colors.white,
                  iconSize: 56,
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FilledButton.tonalIcon(
                    onPressed: busy ? null : onImport,
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_download_outlined),
                    label: const Text('Import from DummyJSON'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Shows the linked DummyJSON product and opens the picker.
class _DummyJsonLinkField extends StatelessWidget {
  const _DummyJsonLinkField({
    required this.dummyId,
    required this.title,
    required this.errorText,
    required this.onPick,
    required this.onClear,
  });

  final int? dummyId;
  final String? title;
  final String? errorText;
  final VoidCallback? onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final id = dummyId;
    return InkWell(
      key: const Key('field_dummyjson'),
      borderRadius: BorderRadius.circular(12),
      onTap: onPick,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Linked DummyJSON product',
          helperText:
              'Shows live rating, warranty and photos from dummyjson.com',
          errorText: errorText,
          prefixIcon: const Icon(Icons.travel_explore),
          suffixIcon: id == null
              ? const Icon(Icons.arrow_drop_down)
              : IconButton(
                  tooltip: 'Unlink',
                  onPressed: onClear,
                  icon: const Icon(Icons.link_off),
                ),
        ),
        isEmpty: id == null,
        child: id == null
            ? null
            : Text(
                title == null ? 'Product #$id' : '$title  (#$id)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
      ),
    );
  }
}
