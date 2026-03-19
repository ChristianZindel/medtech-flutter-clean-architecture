import 'entry.dart';

class SuggestionService {
  /// Liefert eine passende Empfehlung basierend auf Score und aktuellem Eintrag.
  String getSuggestion(int score, Entry? latest) {
    if (latest == null) return '';

    final suggestions = <String>[];

    // Spezifische Checks basierend auf den Werten
    if (latest.sleepHours < 6) {
      suggestions.add('Achte heute auf bewusste Erholungspausen.');
    }
    if (latest.energy <= 3) {
      suggestions.add('Kleine Inseln ohne Reize (Handy weg) können den Akku stützen.');
    }
    if (latest.stress >= 7) {
      suggestions.add('Versuche, kurz innezuhalten und tief durchzuatmen.');
    }

    // Rückgabe basierend auf dem Gesamt-Risiko-Score
    if (score >= 75) {
      return suggestions.isNotEmpty
          ? suggestions.first
          : 'Die aktuelle Belastung ist sehr hoch. Priorisiere deine Grundbedürfnisse.';
    }
    if (score >= 50) {
      return suggestions.isNotEmpty
          ? suggestions.first
          : 'Achte heute auf klare Grenzen und Mini-Pausen.';
    }
    if (score >= 30) {
      return suggestions.isNotEmpty
          ? suggestions.first
          : 'Stabiler Tag – ein kurzer Moment der Selbstfürsorge hält das Level.';
    }

    return 'Guter Verlauf – behalte deine Routine bei, ohne Druck.';
  }
}