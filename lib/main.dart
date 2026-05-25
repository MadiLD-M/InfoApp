import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const InfoApp());
}

class InfoApp extends StatelessWidget {
  const InfoApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF0F5C63);
    const secondary = Color(0xFF287C83);
    const accent = Color(0xFFE9B44C);

    return MaterialApp(
      title: 'InfoApp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.light,
          primary: primary,
          secondary: secondary,
          tertiary: accent,
          surface: const Color(0xFFF7FAFA),
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F7F7),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor: Color(0xFFF3F7F7),
          foregroundColor: Color(0xFF173236),
        ),
      ),
      home: const ModulesHomePage(),
    );
  }
}

class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.name,
    this.iconBase64,
  });

  factory InstalledApp.fromMap(Map<dynamic, dynamic> map) {
    return InstalledApp(
      packageName: map['packageName'] as String,
      name: map['name'] as String,
      iconBase64: map['icon'] as String?,
    );
  }

  final String packageName;
  final String name;
  final String? iconBase64;

  Uint8List? get iconBytes {
    final icon = iconBase64;
    if (icon == null || icon.isEmpty) {
      return null;
    }
    return base64Decode(icon);
  }
}

class AppLauncherService {
  static const _channel = MethodChannel('infoapp/app_launcher');

  Future<List<InstalledApp>> getInstalledApps() async {
    final apps = await _channel.invokeListMethod<dynamic>('getInstalledApps');
    return (apps ?? const <dynamic>[])
        .cast<Map<dynamic, dynamic>>()
        .map(InstalledApp.fromMap)
        .toList();
  }

  Future<List<String>> getSavedApps() async {
    final packages = await _channel.invokeListMethod<String>('getSavedApps');
    return packages ?? const <String>[];
  }

  Future<Map<String, String>> getAppDescriptions() async {
    final descriptions = await _channel.invokeMapMethod<String, String>(
      'getAppDescriptions',
    );
    return descriptions ?? const <String, String>{};
  }

  Future<void> saveApps(List<String> packageNames) {
    return _channel.invokeMethod<void>('saveApps', packageNames);
  }

  Future<void> saveAppDescription(String packageName, String description) {
    return _channel.invokeMethod<void>('saveAppDescription', {
      'packageName': packageName,
      'description': description,
    });
  }

  Future<bool> launchApp(String packageName) async {
    final opened = await _channel.invokeMethod<bool>('launchApp', packageName);
    return opened ?? false;
  }
}

class ModulesHomePage extends StatefulWidget {
  const ModulesHomePage({super.key});

  @override
  State<ModulesHomePage> createState() => _ModulesHomePageState();
}

class _ModulesHomePageState extends State<ModulesHomePage> {
  final _service = AppLauncherService();
  List<InstalledApp> _installedApps = const [];
  List<String> _selectedPackages = const [];
  Map<String, String> _descriptions = const {};
  bool _isLoading = true;
  String? _error;

  List<InstalledApp> get _modules {
    final selected = _selectedPackages.toSet();
    return _installedApps
        .where((app) => selected.contains(app.packageName))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _service.getInstalledApps(),
        _service.getSavedApps(),
        _service.getAppDescriptions(),
      ]);

      final installed = results[0] as List<InstalledApp>;
      final saved = (results[1] as List<String>).toSet();
      final descriptions = results[2] as Map<String, String>;
      final availablePackages = installed.map((app) => app.packageName).toSet();

      if (!mounted) {
        return;
      }
      setState(() {
        _installedApps = installed;
        _selectedPackages = saved
            .where(availablePackages.contains)
            .toList(growable: false);
        _descriptions = Map.unmodifiable(descriptions);
        _isLoading = false;
      });
    } on PlatformException catch (exception) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = exception.message ?? 'No se pudieron cargar las aplicaciones.';
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'No se pudieron cargar las aplicaciones.';
        _isLoading = false;
      });
    }
  }

  Future<void> _removeModule(InstalledApp app) async {
    final updated = _selectedPackages
        .where((packageName) => packageName != app.packageName)
        .toList(growable: false);

    await Future.wait([
      _service.saveApps(updated),
      _service.saveAppDescription(app.packageName, ''),
    ]);

    if (!mounted) {
      return;
    }
    setState(() {
      _selectedPackages = updated;
      _descriptions = Map.unmodifiable(
        Map<String, String>.from(_descriptions)..remove(app.packageName),
      );
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${app.name} se elimino del menu.')));
  }

  Future<void> _editDescription(InstalledApp app) async {
    final controller = TextEditingController(
      text: _descriptions[app.packageName] ?? '',
    );

    final description = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(app.name),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            maxLength: 140,
            decoration: const InputDecoration(
              labelText: 'Descripcion',
              hintText: 'Ej. Ventas, inventario, reportes...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (description == null) {
      return;
    }

    await _service.saveAppDescription(app.packageName, description);
    if (!mounted) {
      return;
    }

    setState(() {
      final updated = Map<String, String>.from(_descriptions);
      if (description.isEmpty) {
        updated.remove(app.packageName);
      } else {
        updated[app.packageName] = description;
      }
      _descriptions = Map.unmodifiable(updated);
    });
  }

  Future<void> _openModule(InstalledApp app) async {
    final opened = await _service.launchApp(app.packageName);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo abrir ${app.name}.')));
    }
  }

  Future<void> _showAppPicker() async {
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return AppPickerSheet(
          apps: _installedApps,
          selectedPackages: _selectedPackages,
        );
      },
    );

    if (selected == null) {
      return;
    }

    await _service.saveApps(selected);
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedPackages = selected;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final bool manyModules = _modules.length >= 5;

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: manyModules
              ? Opacity(
                  opacity: 0.20,
                  child: IconButton(
                    tooltip: 'Agregar modulo',
                    icon: const Icon(Icons.add_rounded, size: 16),
                    style: IconButton.styleFrom(
                      foregroundColor: const Color(0xFF888888),
                      minimumSize: const Size(32, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _isLoading ? null : _showAppPicker,
                  ),
                )
              : IconButton.filledTonal(
                  tooltip: 'Agregar modulo',
                  icon: const Icon(Icons.add_rounded),
                  onPressed: _isLoading ? null : _showAppPicker,
                ),
        ),
        title: const Text('InfoApp'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadApps,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadApps,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: HeaderPanel(moduleCount: _modules.length),
                ),
              ),
              if (_isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Algo salio mal',
                    message: _error!,
                    actionLabel: 'Reintentar',
                    onAction: _loadApps,
                  ),
                )
              else if (_modules.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.dashboard_customize_outlined,
                    title: 'Agrega tus modulos',
                    message:
                        'Selecciona las aplicaciones que forman parte del ERP.',
                    actionLabel: 'Agregar',
                    onAction: _showAppPicker,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  sliver: SliverGrid.builder(
                    itemCount: _modules.length,
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          mainAxisExtent: 198,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                    itemBuilder: (context, index) {
                      final app = _modules[index];
                      return ModuleTile(
                        app: app,
                        color: index.isEven
                            ? colorScheme.primary
                            : colorScheme.secondary,
                        description: _descriptions[app.packageName],
                        onTap: () => _openModule(app),
                        onEditDescription: () => _editDescription(app),
                        onDelete: () => _removeModule(app),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class HeaderPanel extends StatelessWidget {
  const HeaderPanel({super.key, required this.moduleCount});

  final int moduleCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(
            'InfoAPP.png',
            height: 100, // Altura del banner
            fit: BoxFit.cover, // Asegurar que cubra bien si es un banner
            alignment: Alignment.center,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE3EEEE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'InfoAPP',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF173236),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ofrece una solución ERP que ayuda a las empresas a gestionar de forma más ordenada y eficiente sus procesos de calidad, mantenimiento, permisos de trabajo, competencias y certificaciones laborales.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF526B70)),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Icon(Icons.apps_rounded, color: colorScheme.tertiary),
                  const SizedBox(width: 8),
                  Text(
                    moduleCount == 1
                        ? '1 modulo activo'
                        : '$moduleCount modulos activos',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ModuleTile extends StatefulWidget {
  const ModuleTile({
    super.key,
    required this.app,
    required this.color,
    required this.description,
    required this.onTap,
    required this.onEditDescription,
    required this.onDelete,
  });

  final InstalledApp app;
  final Color color;
  final String? description;
  final VoidCallback onTap;
  final VoidCallback onEditDescription;
  final VoidCallback onDelete;

  @override
  State<ModuleTile> createState() => _ModuleTileState();
}

class _ModuleTileState extends State<ModuleTile> {
  static const _actionWidth = 112.0;
  double _slideOffset = 0;

  bool get _isOpen => _slideOffset < -_actionWidth / 2;

  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      _slideOffset = (_slideOffset + details.delta.dx).clamp(-_actionWidth, 0);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    setState(() {
      _slideOffset = _isOpen ? -_actionWidth : 0;
    });
  }

  void _close() {
    setState(() => _slideOffset = 0);
  }

  @override
  Widget build(BuildContext context) {
    final description = widget.description?.trim();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFF7FAFA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE0EBEC)),
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: _actionWidth,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Editar descripcion',
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFFFF5DA),
                          foregroundColor: const Color(0xFF7B5200),
                        ),
                        icon: const Icon(Icons.edit_note_rounded),
                        onPressed: () {
                          _close();
                          widget.onEditDescription();
                        },
                      ),
                      const SizedBox(width: 6),
                      IconButton.filledTonal(
                        tooltip: 'Eliminar del menu',
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFFFE8E6),
                          foregroundColor: const Color(0xFFB42318),
                        ),
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () {
                          _close();
                          widget.onDelete();
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            left: _slideOffset,
            right: -_slideOffset,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              onHorizontalDragUpdate: _handleDragUpdate,
              onHorizontalDragEnd: _handleDragEnd,
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _isOpen ? _close : widget.onTap,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE0EBEC)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppIcon(
                          app: widget.app,
                          size: 52,
                          fallbackColor: widget.color,
                        ),
                        const Spacer(),
                        Text(
                          widget.app.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: const Color(0xFF173236),
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          description == null || description.isEmpty
                              ? 'Abrir modulo'
                              : description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color:
                                    description == null || description.isEmpty
                                    ? widget.color
                                    : const Color(0xFF526B70),
                                fontWeight:
                                    description == null || description.isEmpty
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppPickerSheet extends StatefulWidget {
  const AppPickerSheet({
    super.key,
    required this.apps,
    required this.selectedPackages,
  });

  final List<InstalledApp> apps;
  final List<String> selectedPackages;

  @override
  State<AppPickerSheet> createState() => _AppPickerSheetState();
}

class _AppPickerSheetState extends State<AppPickerSheet> {
  late final Set<String> _selected = widget.selectedPackages.toSet();
  String _query = '';

  List<InstalledApp> get _filteredApps {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return widget.apps;
    }
    return widget.apps
        .where((app) => app.name.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      maxChildSize: 0.96,
      minChildSize: 0.5,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Agregar modulos',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF173236),
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop(_selected.toList()..sort());
                    },
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Guardar'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Buscar aplicacion',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                itemCount: _filteredApps.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final app = _filteredApps[index];
                  final checked = _selected.contains(app.packageName);
                  return CheckboxListTile(
                    value: checked,
                    activeColor: colorScheme.primary,
                    secondary: AppIcon(
                      app: app,
                      size: 42,
                      fallbackColor: colorScheme.secondary,
                    ),
                    title: Text(
                      app.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      app.packageName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onChanged: (value) {
                      setState(() {
                        if (value ?? false) {
                          _selected.add(app.packageName);
                        } else {
                          _selected.remove(app.packageName);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class AppIcon extends StatelessWidget {
  const AppIcon({
    super.key,
    required this.app,
    required this.size,
    required this.fallbackColor,
  });

  final InstalledApp app;
  final double size;
  final Color fallbackColor;

  @override
  Widget build(BuildContext context) {
    final bytes = app.iconBytes;

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: fallbackColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: bytes == null
          ? Icon(Icons.apps_rounded, color: fallbackColor, size: size * 0.56)
          : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 54, color: colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF173236),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF526B70)),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.add_rounded),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}
