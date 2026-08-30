pipeline {
  agent none

  options {
    disableConcurrentBuilds()
    skipDefaultCheckout(true)
    timeout(time: 10, unit: 'MINUTES')
    timestamps()
  }

  stages {
    stage('Validate') {
      agent { label 'linux' }
      steps {
        checkout scm
        sh '''
          if [ -n "${CHANGE_ID:-}" ]; then
            case "$CHANGE_ID" in
              *[!0-9]*) printf 'Invalid CHANGE_ID: %s\\n' "$CHANGE_ID" >&2; exit 1 ;;
            esac
            git check-ref-format --branch "$CHANGE_TARGET" >/dev/null
            git fetch --no-tags origin \
              "+refs/heads/$CHANGE_TARGET:refs/remotes/origin/$CHANGE_TARGET" \
              "+refs/pull/$CHANGE_ID/head:refs/remotes/origin/pr/$CHANGE_ID/head"
            git checkout --detach "refs/remotes/origin/pr/$CHANGE_ID/head"
          fi
          bash scripts/verify.sh
          if [ -n "${CHANGE_ID:-}" ]; then
            bash scripts/verify-pr-diff.sh \
              "refs/remotes/origin/$CHANGE_TARGET" \
              "refs/remotes/origin/pr/$CHANGE_ID/head"
          fi
        '''
      }
    }
  }
}
