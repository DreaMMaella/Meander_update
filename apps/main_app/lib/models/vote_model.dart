enum VoteType { like, dislike, none }

class UserVote {
  final VoteType voteType;

  UserVote(this.voteType);
}
