import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme.dart';

/// Curated 32-emoji picker with optional custom emoji input.
class EmojiPickerGrid extends StatefulWidget {
  final String selectedEmoji;
  final ValueChanged<String> onSelected;

  const EmojiPickerGrid({
    super.key,
    required this.selectedEmoji,
    required this.onSelected,
  });

  @override
  State<EmojiPickerGrid> createState() => _EmojiPickerGridState();
}

class _EmojiPickerGridState extends State<EmojiPickerGrid> {
  bool _showCustomInput = false;
  final _customCtrl = TextEditingController();

  static const _people = [
    '👶', '🧒', '👧', '👦',
    '👩', '👨', '👩‍🦱', '👨‍🦱',
    '👩‍🦳', '👨‍🦳', '👵', '👴',
    '🧑‍🍼', '👩‍💻', '👨‍🍳', '🧑‍🎤',
  ];

  static const _others = [
    '🦁', '🐯', '🐼', '🦊',
    '🌸', '🌻', '⭐', '🌈',
    '🎸', '🎮', '🚀', '📚',
    '🍕', '☕', '🎨', '⚽',
  ];

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  void _onCustomSubmit() {
    final text = _customCtrl.text.trim();
    if (text.isEmpty) return;
    final runes = text.runes.toList();
    if (runes.isEmpty) return;
    final first = String.fromCharCode(runes.first);
    widget.onSelected(first.trim().isEmpty ? text : first);
    setState(() => _showCustomInput = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('People & Family'),
        const SizedBox(height: 10),
        _EmojiGrid(
          emojis: _people,
          selected: widget.selectedEmoji,
          onTap: widget.onSelected,
        ),
        const SizedBox(height: 20),
        _sectionLabel('Animals, Hobbies & More'),
        const SizedBox(height: 10),
        _EmojiGrid(
          emojis: _others,
          selected: widget.selectedEmoji,
          onTap: widget.onSelected,
        ),
        const SizedBox(height: 16),
        if (!_showCustomInput)
          GestureDetector(
            onTap: () => setState(() => _showCustomInput = true),
            child: Text(
              'Use a different emoji',
              style: GoogleFonts.dmSans(
                color: AppColors.primary,
                fontSize: 13,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.primary,
              ),
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customCtrl,
                  autofocus: true,
                  maxLength: 8,
                  style: const TextStyle(fontSize: 22),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Type any emoji',
                    hintStyle: GoogleFonts.dmSans(
                      color: AppColors.textMuted,
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.cardBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _onCustomSubmit(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _onCustomSubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'Use',
                  style: GoogleFonts.dmSans(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: AppColors.textMuted,
                  size: 20,
                ),
                onPressed: () => setState(() {
                  _showCustomInput = false;
                  _customCtrl.clear();
                }),
              ),
            ],
          ),
      ],
    );
  }

  Widget _sectionLabel(String label) => Text(
        label,
        style: GoogleFonts.dmSans(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      );
}

class _EmojiGrid extends StatelessWidget {
  final List<String> emojis;
  final String selected;
  final ValueChanged<String> onTap;

  const _EmojiGrid({
    required this.emojis,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: emojis.map((e) {
        final isSelected = selected == e;
        return GestureDetector(
          onTap: () => onTap(e),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.cardBorder,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Center(
              child: Text(e, style: const TextStyle(fontSize: 24)),
            ),
          ),
        );
      }).toList(),
    );
  }
}
