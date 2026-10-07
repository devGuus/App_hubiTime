/// Constantes compartilhadas com o site (hubi-time-web/src/lib/constants.ts).
/// Mesmos valores gravados no banco - nunca renomear as chaves.
library;

enum DayType {
  normal('normal', 'Dia normal'),
  folga('folga', 'Folga'),
  ferias('ferias', 'Férias'),
  feriado('feriado', 'Feriado'),
  atestado('atestado', 'Atestado'),
  ausencia('ausencia', 'Ausência'),
  outro('outro', 'Outro');

  const DayType(this.key, this.label);
  final String key;
  final String label;

  static DayType fromKey(String? key) =>
      DayType.values.firstWhere((t) => t.key == key, orElse: () => DayType.normal);

  /// Só o dia normal tem jornada prevista (mesma regra do site).
  bool get countsAsExpectedWorkday => this == DayType.normal;
}

enum WeekdayKey {
  segunda('segunda', 'Segunda-feira', 'Seg'),
  terca('terca', 'Terça-feira', 'Ter'),
  quarta('quarta', 'Quarta-feira', 'Qua'),
  quinta('quinta', 'Quinta-feira', 'Qui'),
  sexta('sexta', 'Sexta-feira', 'Sex'),
  sabado('sabado', 'Sábado', 'Sáb'),
  domingo('domingo', 'Domingo', 'Dom');

  const WeekdayKey(this.key, this.label, this.shortLabel);
  final String key;
  final String label;
  final String shortLabel;

  /// [DateTime.weekday]: 1 = segunda ... 7 = domingo.
  static WeekdayKey fromDartWeekday(int weekday) => WeekdayKey.values[weekday - 1];
}

const Map<WeekdayKey, double> defaultWeeklyHours = {
  WeekdayKey.segunda: 8,
  WeekdayKey.terca: 8,
  WeekdayKey.quarta: 8,
  WeekdayKey.quinta: 8,
  WeekdayKey.sexta: 8,
  WeekdayKey.sabado: 0,
  WeekdayKey.domingo: 0,
};

const defaultMonthlyHours = 220;

const monthLabelsPt = [
  'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
  'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
];

/// Rótulos das notificações do site (user_settings.notifications_enabled).
const notificationLabels = {
  'missing_lunch_return': 'Avisar quando faltar registrar o retorno do almoço',
  'incomplete_today': 'Avisar quando o registro do dia estiver incompleto',
  'time_inconsistency': 'Avisar sobre horários inconsistentes',
  'incomplete_month': 'Avisar sobre registros incompletos no mês',
};
