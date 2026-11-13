import 'package:material_ui/material_ui.dart';

import '../ui/theme.dart';
import '../ui/widgets/aurora_background.dart';
import 'downloads_screen.dart';
import 'home_screen.dart';

/// Навигационная оболочка: поиск и загрузки живут как вкладки,
/// фон — общий анимированный градиент.
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key, this.animateBackground = true});

  final bool animateBackground;

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      animate: widget.animateBackground,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: IndexedStack(
          index: _index,
          children: const [
            HomeScreen(key: Key('tab-search')),
            DownloadsScreen(key: Key('tab-downloads')),
          ],
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xE60A0F1A),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: AppColors.stroke),
              ),
              child: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.travel_explore_outlined),
                    selectedIcon: Icon(Icons.travel_explore),
                    label: 'Поиск',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.download_for_offline_outlined),
                    selectedIcon: Icon(Icons.download_for_offline),
                    label: 'Загрузки',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
