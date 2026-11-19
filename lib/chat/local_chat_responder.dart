/// Small, offline keyword responder for the OVA chat demo.
///
/// This is intentionally a fixed set of educational replies, not an AI model.
class LocalChatResponder {
  LocalChatResponder._();

  static String replyTo(String message) {
    final text = _normalize(message);
    final paddedText = ' $text ';

    bool hasAny(List<String> keywords) => _hasAny(text, keywords);

    if (hasAny([
      'chest pain',
      'trouble breathing',
      'shortness of breath',
      'fainting',
      'faint',
      'fainted',
      'passed out',
      'suicide',
      'suicidal',
      'self harm',
      'kill myself',
      'hurt myself',
    ])) {
      return 'I’m really sorry this is happening. Chest pain, trouble breathing, fainting, or feeling at risk of harming yourself needs immediate support. Please contact local emergency services now, or ask someone you trust nearby to help you get care. You don’t have to handle this alone.';
    }

    if (hasAny([
      'heavy bleeding',
      'heavy flow',
      'very heavy',
      'soaking a pad',
      'soaking pads',
      'soaking a tampon',
      'bleeding every hour',
      'dizzy and bleeding',
      'lightheaded and bleeding',
    ])) {
      return 'That sounds frightening and exhausting. Very heavy bleeding, especially with dizziness or feeling faint, needs prompt medical attention. If you feel faint, have chest pain, or have trouble breathing, seek emergency care now. Otherwise, please contact a healthcare professional promptly; if you can, ask someone you trust to support you.';
    }

    if (hasAny(['hello', 'hi', 'hey', 'good morning', 'good evening'])) {
      return 'Hi, I’m OVA 🌷 I’m glad you’re here. I can share a few prepared, general tips about periods and menstrual cycles. What’s on your mind today?';
    }

    if (hasAny(['thank you', 'thanks', 'thx'])) {
      return 'You’re very welcome 💛 I’m glad you asked. Is there another period or cycle question on your mind?';
    }

    if (hasAny(['track', 'tracking', 'calendar', 'cycle day', 'period log'])) {
      return 'Absolutely—a gentle place to start is marking the first day of bleeding as day 1. You can also note when it ends and any symptoms you want to remember. After a few cycles, you may notice a pattern; predictions are still estimates. No need to track everything perfectly.';
    }

    if (isPeriodTimingQuestion(message)) {
      final opening =
          _hasAny(text, [
            'yesterday',
            'due yesterday',
            'expected yesterday',
            'was supposed to start yesterday',
            'was supposed to come yesterday',
            'about to be on',
          ])
          ? 'That can feel worrying, especially when you expected it yesterday.'
          : 'It can feel unsettling when your period timing is unpredictable.';
      return '$opening Dates can shift, and a calendar estimate is not an exact promise. Have you used the four-marker Assay Scan in this app (LH, E3G, PdG, and FSH)? If yes, reply “yes” and I’ll look at any chart points loaded in this app session. One important note: this version’s Assay Scan uses simulated demo readings, not a real test or connected device, so I can only describe that sample chart-not identify a medical cause from it. If pregnancy is possible, a home test may help; follow its instructions. If your period stops for 3 months or this pattern keeps changing, please check in with a healthcare professional.';
    }

    if (hasAny(['pregnant', 'pregnancy'])) {
      return 'It makes sense to have questions. I can’t tell whether you’re pregnant from a chat. If pregnancy is possible and your period is late, a home pregnancy test may help; follow its instructions. If you’re worried, a healthcare professional can help you work through next steps.';
    }

    if (hasAny([
      'hormone',
      'hormones',
      'hormonal',
      'estrogen',
      'oestrogen',
      'progesterone',
    ])) {
      return 'It makes sense to want to understand what’s happening in your body. Hormones such as estrogen and progesterone naturally shift through the cycle and can affect bleeding and symptoms. OVA and cycle charts can’t measure hormone levels or diagnose an imbalance. If you’re concerned, noting your period dates and symptoms can give you something useful to discuss with a healthcare professional; they can decide whether tests are needed. Please don’t change treatment based on an app prediction. What changes made you curious about your hormones?';
    }

    if (hasAny([
      'irregular',
      'not on time',
      'not having my periods on time',
      'periods are not on time',
      'periods not on time',
      'periods are not regular',
      'period is not regular',
      'periods are irregular',
      'periods irregular',
      'periods are late',
      'period does not come on time',
      'not getting my period on time',
      'not getting periods on time',
      'cycle length',
      'cycle',
      'how long is a cycle',
      'normal cycle',
      'days between periods',
      'period every',
    ])) {
      return 'That can feel frustrating or worrying, especially when your timing changes unexpectedly. A cycle is counted from the first day of one period to the first day of the next, and patterns can vary. ACOG describes 21–35 days as typical for adults and 21–45 days for teens. There can be many reasons for a change, and I can’t tell the cause from chat. If previously regular periods become irregular for several months, cycles are repeatedly shorter than 21 days or longer than 35 days in adults, or you go 3 months without a period, please check in with a healthcare professional. If pregnancy is possible and a period is missed, a home test may help. You deserve clear answers and support.';
    }

    if (hasAny([
      'cramp',
      'cramps',
      'cramping',
      'period pain',
      'painful period',
    ])) {
      return 'I’m sorry you’re uncomfortable—cramps can make the day feel harder. I can’t tell what’s causing your pain, but rest, gentle movement, or a warm pack may feel soothing. If the pain is severe, new, worsening, persistent, or disrupting daily life, please talk with a healthcare professional. You don’t have to just put up with it.';
    }

    if (hasAny(['pms', 'premenstrual', 'mood before my period', 'bloating'])) {
      return 'Those before-period changes can be tiring, and you deserve support. Some people notice mood or body changes in the days before a period. Jotting down when they happen may help you explain the pattern to a clinician. If they feel intense or get in the way of daily life, a healthcare professional can help you explore what might help.';
    }

    if (hasAny(['ovulation', 'fertile', 'fertility', 'fertile window'])) {
      return 'It’s understandable to wonder about ovulation and timing. Cycle apps can only estimate ovulation from dates; they can’t confirm it, predict pregnancy, or reliably prevent pregnancy. For fertility or contraception decisions, a qualified healthcare professional can help you find information that fits your situation.';
    }

    if (hasAny(['discharge', 'itching', 'itch', 'odor', 'smell'])) {
      return 'It’s okay to ask about changes like this. Discharge can vary, but I can’t assess symptoms here. If a change is new or persistent, or you have itching, pain, or a strong odor, consider contacting a healthcare professional for reassurance and guidance.';
    }

    if (hasAny([
      'birth control',
      'contraception',
      'missed pill',
      'medication',
      'medicine',
      'treatment',
    ])) {
      return 'I’m glad you checked before changing anything. I can’t advise you to start, stop, or change medication or contraception. The product instructions, a pharmacist, or a healthcare professional can help you choose a safe next step for your situation.';
    }

    if (hasAny(['stress', 'anxious', 'overwhelmed', 'sad', 'mood'])) {
      return 'That sounds like a lot to carry. Take your time—there’s no need to explain it perfectly. If you’d like, tell me a little more about what’s been on your mind. I can offer general support, though I’m not a therapist or a healthcare professional.';
    }

    return 'I may not have picked up on that yet, but we can try another way. I understand prepared topics like tracking your cycle, hormones, irregular or late periods, cramps, PMS, ovulation, and discharge. Try rephrasing with one of those words. I can share general information, but I can’t diagnose.';
  }

  static bool isPeriodTimingQuestion(String message) {
    final text = _normalize(message);
    final mentionsCycle = _hasAny(text, [
      'period',
      'periods',
      'cycle',
      'menstrual',
    ]);
    final mentionsTimingConcern = _hasAny(text, [
      'late',
      'delayed',
      'delay',
      'overdue',
      'missed',
      'due',
      'not getting',
      'not having',
      'not on time',
      'not arriving on time',
      'isn t getting',
      'is not getting',
      'has not started',
      'hasn t started',
      'have not had',
      'haven t had',
      'irregular',
      'not regular',
      'three months',
      '3 months',
      'about to be on',
      'expected yesterday',
      'due yesterday',
    ]);
    return _hasAny(text, [
          'late period',
          'missed period',
          'period late',
          'my period is late',
          'not getting my periods on time',
          'not getting my period on time',
          'period was due yesterday',
          'period due yesterday',
          'period should have started',
          'period has not started',
        ]) ||
        (mentionsCycle && mentionsTimingConcern);
  }

  static bool isAffirmative(String message) => _hasAny(_normalize(message), [
    'yes',
    'yeah',
    'yep',
    'yup',
    'i did',
    'i have',
    'i have done it',
    'done',
    'completed',
    'i took the test',
    'i used it',
  ]);

  static bool isNegative(String message) => _hasAny(_normalize(message), [
    'no',
    'nope',
    'not yet',
    'i haven t',
    'i have not',
    'i didn t',
    'i did not',
    'haven t',
    'have not',
    'not done',
  ]);

  static String noAssayReply() =>
      'That’s completely okay—you don’t need a test to deserve support. The Assay Scan in this demo app is simulated and can’t run a real hormone test. For now, noting period start dates and symptoms can help you see whether the timing change repeats. If pregnancy is possible, a home test may help. If your period stops for 3 months or the changes continue, please check with a healthcare professional.';

  static String reviewAssayChart(Map<int, Map<String, double>> scannedResults) {
    if (scannedResults.isEmpty) {
      return 'Okay, I checked what’s loaded in this app session, but I don’t see a four-marker scan yet. The Assay Scan screen currently creates simulated demo readings; it doesn’t connect to a physical test or accept real lab results. So I can’t review your actual hormone results yet. I can still share general information, and a healthcare professional can help investigate repeated cycle changes.';
    }

    final entries = scannedResults.entries.toList()
      ..sort((first, second) => first.key.compareTo(second.key));
    const markers = ['LH', 'E3G', 'PdG', 'FSH'];
    final first = entries.first;
    final latest = entries.last;
    final latestValues = markers
        .where((marker) => latest.value.containsKey(marker))
        .map(
          (marker) =>
              '$marker ${latest.value[marker]!.toStringAsFixed(0)} demo index',
        )
        .join(', ');

    var patternSummary = 'I found one demo point in this session';
    if (entries.length > 1) {
      final trends = <String>[];
      for (final marker in markers) {
        final start = first.value[marker];
        final end = latest.value[marker];
        if (start == null || end == null) continue;
        final direction = end > start + 2
            ? 'rose'
            : end < start - 2
            ? 'fell'
            : 'stayed similar';
        trends.add('$marker $direction');
      }
      patternSummary =
          'Across ${entries.length} demo points loaded here (cycle day ${first.key} to ${latest.key}), ${trends.join(', ')}';
    }

    return 'Okay, I’ve checked the chart pattern with you. $patternSummary. The latest sample on cycle day ${latest.key} shows $latestValues. Please remember these are generated demo indices, not measurements from your body or a real test. They can’t show a probable medical cause for a late period. Possible contributors to irregular periods include stress, pregnancy, some medicines, PCOS, thyroid conditions, and changes in eating or exercise; a clinician can help assess which, if any, apply. If you have a real test result, it isn’t connected to OVA in this version yet.';
  }

  static bool _hasAny(String normalizedText, List<String> keywords) {
    final paddedText = ' $normalizedText ';
    return keywords.any((keyword) {
      final normalizedKeyword = _normalize(keyword);
      return paddedText.contains(' $normalizedKeyword ');
    });
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
