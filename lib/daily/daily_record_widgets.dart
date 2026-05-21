import 'package:flutter/material.dart';
import '../constants/healing_design_system.dart';

// ============================================================
// UI Widgets
// ============================================================

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {this.trailing, Key? key}) : super(key: key);
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HealingDesignSystem.paddingL,
        HealingDesignSystem.paddingL,
        HealingDesignSystem.paddingL,
        HealingDesignSystem.paddingM,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: HealingDesignSystem.titleLarge.copyWith(
                color: HealingDesignSystem.adaptivePrimaryText(context),
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class RecordHeader extends StatelessWidget {
  const RecordHeader({
    super.key,
    required this.dateText,
    required this.timeText,
    required this.onPickDate,
    required this.onPickTime,
  });

  final String dateText;
  final String timeText;
  final Future<void> Function() onPickDate;
  final Future<void> Function() onPickTime;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HealingDesignSystem.adaptiveFill(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: HealingDesignSystem.paddingM,
          vertical: HealingDesignSystem.paddingM,
        ),
        child: Row(
          children: [
            Expanded(
              child: ListTile(
                dense: true,
                leading: const Icon(
                  Icons.calendar_today,
                  color: HealingDesignSystem.primaryBlue,
                ),
                title: const Text(
                  '日期',
                  style: TextStyle(
                    fontSize: 12,
                    color: HealingDesignSystem.mutedText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  dateText,
                  style: HealingDesignSystem.bodyMedium.copyWith(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                ),
                onTap: () async => await onPickDate(),
              ),
            ),
            Expanded(
              child: ListTile(
                dense: true,
                leading: const Icon(
                  Icons.access_time,
                  color: HealingDesignSystem.primaryBlue,
                ),
                title: const Text(
                  '時間',
                  style: TextStyle(
                    fontSize: 12,
                    color: HealingDesignSystem.mutedText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  timeText,
                  style: HealingDesignSystem.bodyMedium.copyWith(
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                ),
                onTap: () async => await onPickTime(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {Key? key}) : super(key: key);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: HealingDesignSystem.titleSmall.copyWith(
        color: HealingDesignSystem.adaptivePrimaryText(context),
      ),
    );
  }
}

class TimeTile extends StatelessWidget {
  const TimeTile({
    Key? key,
    required this.label,
    required this.timeText,
    required this.onTap,
  }) : super(key: key);

  final String label;
  final String timeText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: HealingDesignSystem.paddingL,
            vertical: HealingDesignSystem.paddingM,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: HealingDesignSystem.bodyMedium.copyWith(
                  color: HealingDesignSystem.adaptiveSecondaryText(context),
                ),
              ),
              Text(
                timeText,
                style: HealingDesignSystem.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: HealingDesignSystem.adaptiveAccent(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ListTileButton extends StatelessWidget {
  const ListTileButton(
      {super.key,
      required this.label,
      required this.valueText,
      required this.onTap});

  final String label;
  final String valueText;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusL),
        child: Ink(
          decoration: HealingDesignSystem.adaptiveCardDecoration(context),
          child: Padding(
            padding: const EdgeInsets.all(HealingDesignSystem.paddingL),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: HealingDesignSystem.labelMedium.copyWith(
                          color: HealingDesignSystem.adaptiveSecondaryText(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        valueText,
                        style: HealingDesignSystem.bodyMedium.copyWith(
                          color: HealingDesignSystem.adaptivePrimaryText(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down,
                  color: HealingDesignSystem.adaptiveAccent(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SaveHintButton extends StatelessWidget {
  const SaveHintButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: HealingDesignSystem.primaryGradient(),
        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusL),
        boxShadow: [HealingDesignSystem.shadowMedium()],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(HealingDesignSystem.radiusL),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: HealingDesignSystem.paddingL,
              vertical: HealingDesignSystem.paddingM,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.save_outlined,
                  color: Colors.white,
                ),
                const SizedBox(width: HealingDesignSystem.paddingM),
                const Text(
                  '儲存',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
