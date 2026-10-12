abstract class Failure {
  final String message;
  Failure(this.message);
}

class ServerFailure extends Failure {
  ServerFailure(super.message);
}

class UnauthorizedFailure extends Failure {
  UnauthorizedFailure(super.message);
}
