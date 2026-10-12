import 'package:dartz/dartz.dart';
import '../../core/error/failures.dart';
import '../entities/report_entity.dart';

abstract class ReportRepository {
  Future<Either<Failure, IncomeStatementEntity>> getIncomeStatement(
      String userRole);
}
