import '../../domain/entities/report_entity.dart';

class IncomeStatementModel extends IncomeStatementEntity {
  IncomeStatementModel({
    required super.totalRevenue,
    required super.totalExpense,
    required super.netProfit,
  });

  factory IncomeStatementModel.fromJson(Map<String, dynamic> json) {
    return IncomeStatementModel(
      totalRevenue: json['totalRevenue'] ?? 0,
      totalExpense: json['totalExpense'] ?? 0,
      netProfit: json['netProfit'] ?? 0,
    );
  }
}
