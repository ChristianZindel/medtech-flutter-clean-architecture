import 'dart:math';

class Entry {
  final String date;
  final int energy;
  final int stress;
  final double sleepHours;
  final int mood;
  final List<String> symptoms;
  final List<String> actions;
  final String notes;
  final String updatedAt;

  Entry({
    required this.date,
    required this.energy,
    required this.stress,
    required this.sleepHours,
    required this.mood,
    required this.symptoms,
    required this.actions,
    required this.notes,
    required this.updatedAt,
  });

  // Native .clamp() Nutzung & Behalt deiner Logik
  int calculateRiskScore() {
    final energyScore = (10 - energy.clamp(0, 10)) / 10.0;
    final stressScore = stress.clamp(0, 10) / 10.0;
    final sleepScore = ((8 - sleepHours.clamp(0.0, 14.0)) / 8.0).clamp(0.0, 1.0);
    final moodScore = (10 - mood.clamp(0, 10)) / 10.0;

    final symptomBoost = (symptoms.length * 0.04);
    final raw = (0.33 * energyScore) +
        (0.33 * stressScore) +
        (0.20 * sleepScore) +
        (0.14 * moodScore) +
        symptomBoost;

    return (raw.clamp(0.0, 1.0) * 100).round();
  }

  Map<String, dynamic> toJson() => {
    'date': date, 'energy': energy, 'stress': stress,
    'sleepHours': sleepHours, 'mood': mood, 'symptoms': symptoms,
    'actions': actions, 'notes': notes, 'updatedAt': updatedAt,
  };

  static Entry fromJson(Map<String, dynamic> m) => Entry(
    date: m['date'] as String,
    energy: (m['energy'] as num).toInt(),
    stress: (m['stress'] as num).toInt(),
    sleepHours: (m['sleepHours'] as num).toDouble(),
    mood: (m['mood'] as num).toInt(),
    symptoms: (m['symptoms'] as List).map((e) => e.toString()).toList(),
    actions: (m['actions'] as List).map((e) => e.toString()).toList(),
    notes: (m['notes'] ?? '').toString(),
    updatedAt: (m['updatedAt'] ?? '').toString(),
  );
}