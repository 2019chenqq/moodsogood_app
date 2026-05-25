---
---
name: heartshine-theme-system
description: HeartShine adaptive Flutter theme rules
---

# HeartShine Theme System

This Flutter project uses a custom adaptive theme system.

## Core Rules

1. NEVER hardcode colors directly in widgets.
2. ALWAYS use HealingDesignSystem theme-aware colors.
3. All pages must support both light mode and dark mode.
4. Use adaptive background colors instead of fixed white/black.
5. Use soft glassmorphism and low contrast shadows.
6. Maintain calming mental-health-app aesthetics.

---

# Required Theme APIs

## Background

Use:

```dart
HealingDesignSystem.adaptiveBackground(context)