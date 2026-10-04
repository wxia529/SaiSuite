import 'package:flutter/material.dart';

class StudioBanner extends StatelessWidget {
  const StudioBanner(
    this.kicker,
    this.title,
    this.subtitle, {
    super.key,
    this.color = const Color(0xff147d73),
    this.icon = Icons.auto_awesome,
  });
  final String kicker, title, subtitle;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      gradient: LinearGradient(
        colors: [color, Color.lerp(color, const Color(0xff171e3b), .45)!],
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white70),
            const SizedBox(width: 10),
            Text(
              kicker,
              style: const TextStyle(
                color: Colors.white70,
                letterSpacing: 2,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 27,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white70, height: 1.6),
        ),
      ],
    ),
  );
}

class StudioPanel extends StatelessWidget {
  const StudioPanel({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(vertical: 10),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
}

Widget studioChoices(
  List<String> options,
  String value,
  void Function(String) change,
) => Wrap(
  spacing: 8,
  runSpacing: 6,
  children: options
      .map(
        (s) => ChoiceChip(
          label: Text(s),
          selected: s == value,
          onSelected: (_) => change(s),
        ),
      )
      .toList(),
);

Widget studioSlider(
  String label,
  double value,
  double min,
  double max,
  void Function(double) change, {
  int? divisions,
  String? display,
}) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    Row(
      children: [
        Expanded(child: Text(label)),
        Text(display ?? value.round().toString()),
      ],
    ),
    Slider(
      value: value.clamp(min, max),
      min: min,
      max: max,
      divisions: divisions,
      onChanged: change,
    ),
  ],
);
