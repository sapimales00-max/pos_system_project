import 'package:dartz/dartz.dart';
import '../../core/error/failures.dart';
import '../entities/report_entity.dart';
import '../repositories/report_repository.dart';

class GetIncomeStatement {
  final ReportRepository repository;
  GetIncomeStatement(this.repository);

  Future<Either<Failure, IncomeStatementEntity>> execute(String userRole) {
    return repository.getIncomeStatement(userRole);
  }
}
