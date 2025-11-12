# CI/CD Integration Examples

This guide provides complete CI/CD integration examples for using `op-env-manager` with popular CI/CD platforms.

## Table of Contents

- [Prerequisites](#prerequisites)
- [GitHub Actions](#github-actions)
- [GitLab CI](#gitlab-ci)
- [Jenkins](#jenkins)
- [CircleCI](#circleci)
- [Best Practices](#best-practices)

---

## Prerequisites

### 1Password Service Account Setup

All CI/CD integrations require a 1Password Service Account:

1. **Create Service Account**:
   - Log into 1Password
   - Go to **Settings** → **Service Accounts**
   - Click **Create Service Account**
   - Name it (e.g., "GitHub Actions - MyApp")
   - Grant vault access (read-only recommended)
   - Save the token securely

2. **Configure Vault Access**:
   - Grant access only to vaults needed for CI/CD
   - Use read-only permissions (CI shouldn't modify secrets)
   - Create separate service accounts per project/environment

3. **Store Token in CI/CD**:
   - Add token as encrypted secret in your CI/CD platform
   - Name it `OP_SERVICE_ACCOUNT_TOKEN`
   - Never commit or log the token

---

## GitHub Actions

### Basic Workflow

```yaml
# .github/workflows/deploy.yml
name: Deploy with Secrets

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install 1Password CLI
        uses: 1password/install-cli-action@v1

      - name: Install op-env-manager
        run: |
          git clone https://github.com/matteocervelli/op-env-manager.git /tmp/op-env-manager
          sudo ln -s /tmp/op-env-manager/bin/op-env-manager /usr/local/bin/op-env-manager
          op-env-manager version

      - name: Run tests with secrets
        env:
          OP_SERVICE_ACCOUNT_TOKEN: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}
        run: |
          op-env-manager run \
            --vault "Production" \
            --item "myapp" \
            --section "test" \
            -- npm test

      - name: Build application
        env:
          OP_SERVICE_ACCOUNT_TOKEN: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}
        run: |
          op-env-manager run \
            --vault "Production" \
            --item "myapp" \
            --section "build" \
            -- npm run build

      - name: Deploy to production
        if: github.ref == 'refs/heads/main'
        env:
          OP_SERVICE_ACCOUNT_TOKEN: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}
        run: |
          op-env-manager run \
            --vault "Production" \
            --item "myapp" \
            --section "production" \
            -- ./deploy.sh
```

### Multi-Environment Workflow

```yaml
# .github/workflows/multi-env.yml
name: Multi-Environment Deploy

on:
  push:
    branches: [main, staging, develop]

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Determine environment
        id: env
        run: |
          if [ "${{ github.ref }}" = "refs/heads/main" ]; then
            echo "environment=production" >> $GITHUB_OUTPUT
          elif [ "${{ github.ref }}" = "refs/heads/staging" ]; then
            echo "environment=staging" >> $GITHUB_OUTPUT
          else
            echo "environment=development" >> $GITHUB_OUTPUT
          fi

      - name: Install 1Password CLI
        uses: 1password/install-cli-action@v1

      - name: Install op-env-manager
        run: |
          git clone https://github.com/matteocervelli/op-env-manager.git /tmp/op-env-manager
          sudo ln -s /tmp/op-env-manager/bin/op-env-manager /usr/local/bin/op-env-manager

      - name: Deploy with environment-specific secrets
        env:
          OP_SERVICE_ACCOUNT_TOKEN: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}
          APP_ENV: ${{ steps.env.outputs.environment }}
        run: |
          echo "Deploying to $APP_ENV environment"

          # Using $APP_ENV variable for dynamic section selection
          op-env-manager run \
            --vault "Production" \
            --item "myapp" \
            -- ./deploy.sh
```

### Docker Build with Secrets

```yaml
# .github/workflows/docker-build.yml
name: Build Docker Image with Secrets

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Install 1Password CLI
        uses: 1password/install-cli-action@v1

      - name: Install op-env-manager
        run: |
          git clone https://github.com/matteocervelli/op-env-manager.git /tmp/op-env-manager
          sudo ln -s /tmp/op-env-manager/bin/op-env-manager /usr/local/bin/op-env-manager

      - name: Inject secrets for build
        env:
          OP_SERVICE_ACCOUNT_TOKEN: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}
        run: |
          op-env-manager inject \
            --vault "Production" \
            --item "myapp" \
            --section "build" \
            --output .env.build

      - name: Build Docker image
        run: |
          docker build \
            --secret id=env,src=.env.build \
            -t myapp:latest \
            .

      - name: Clean up secrets
        if: always()
        run: rm -f .env.build
```

### Caching op-env-manager

```yaml
# .github/workflows/cached.yml
name: Deploy with Caching

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Cache op-env-manager
        id: cache-op-env-manager
        uses: actions/cache@v3
        with:
          path: /tmp/op-env-manager
          key: op-env-manager-${{ hashFiles('.github/workflows/cached.yml') }}

      - name: Install op-env-manager
        if: steps.cache-op-env-manager.outputs.cache-hit != 'true'
        run: |
          git clone https://github.com/matteocervelli/op-env-manager.git /tmp/op-env-manager

      - name: Link op-env-manager
        run: |
          sudo ln -sf /tmp/op-env-manager/bin/op-env-manager /usr/local/bin/op-env-manager
          op-env-manager version

      - name: Install 1Password CLI
        uses: 1password/install-cli-action@v1

      - name: Deploy
        env:
          OP_SERVICE_ACCOUNT_TOKEN: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}
        run: |
          op-env-manager run \
            --vault "Production" \
            --item "myapp" \
            -- ./deploy.sh
```

---

## GitLab CI

### Basic Pipeline

```yaml
# .gitlab-ci.yml
stages:
  - test
  - build
  - deploy

variables:
  OP_ENV_MANAGER_VERSION: "main"

before_script:
  - apt-get update -qq
  - apt-get install -y -qq curl jq
  # Install 1Password CLI
  - curl -sSfLo op.zip https://cache.agilebits.com/dist/1P/op2/pkg/v2.23.0/op_linux_amd64_v2.23.0.zip
  - unzip -o op.zip -d /usr/local/bin
  - rm op.zip
  # Install op-env-manager
  - git clone https://github.com/matteocervelli/op-env-manager.git /tmp/op-env-manager
  - ln -s /tmp/op-env-manager/bin/op-env-manager /usr/local/bin/op-env-manager
  - op-env-manager version

test:
  stage: test
  script:
    - op-env-manager run --vault "Production" --item "myapp" --section "test" -- npm test
  only:
    - branches

build:
  stage: build
  script:
    - op-env-manager run --vault "Production" --item "myapp" --section "build" -- npm run build
  artifacts:
    paths:
      - dist/
    expire_in: 1 hour
  only:
    - main
    - staging

deploy_production:
  stage: deploy
  script:
    - op-env-manager run --vault "Production" --item "myapp" --section "production" -- ./deploy.sh
  environment:
    name: production
    url: https://myapp.com
  only:
    - main

deploy_staging:
  stage: deploy
  script:
    - op-env-manager run --vault "Production" --item "myapp" --section "staging" -- ./deploy.sh
  environment:
    name: staging
    url: https://staging.myapp.com
  only:
    - staging
```

### Multi-Project with Includes

```yaml
# .gitlab-ci-template.yml
.deploy_template:
  before_script:
    - apt-get update -qq
    - apt-get install -y -qq curl jq
    - curl -sSfLo op.zip https://cache.agilebits.com/dist/1P/op2/pkg/v2.23.0/op_linux_amd64_v2.23.0.zip
    - unzip -o op.zip -d /usr/local/bin
    - rm op.zip
    - git clone https://github.com/matteocervelli/op-env-manager.git /tmp/op-env-manager
    - ln -s /tmp/op-env-manager/bin/op-env-manager /usr/local/bin/op-env-manager
  script:
    - op-env-manager run --vault "$VAULT" --item "$ITEM" --section "$SECTION" -- ./deploy.sh

# .gitlab-ci.yml (in project)
include:
  - project: 'my-group/ci-templates'
    file: '.gitlab-ci-template.yml'

deploy:production:
  extends: .deploy_template
  variables:
    VAULT: "Production"
    ITEM: "myapp"
    SECTION: "production"
  environment: production
  only:
    - main
```

---

## Jenkins

### Declarative Pipeline

```groovy
// Jenkinsfile
pipeline {
    agent any

    environment {
        OP_SERVICE_ACCOUNT_TOKEN = credentials('op-service-account-token')
        VAULT = 'Production'
        ITEM = 'myapp'
    }

    stages {
        stage('Setup') {
            steps {
                script {
                    // Install 1Password CLI
                    sh '''
                        if ! command -v op &> /dev/null; then
                            curl -sSfLo op.zip https://cache.agilebits.com/dist/1P/op2/pkg/v2.23.0/op_linux_amd64_v2.23.0.zip
                            unzip -o op.zip -d /usr/local/bin
                            rm op.zip
                        fi
                    '''

                    // Install op-env-manager
                    sh '''
                        if ! command -v op-env-manager &> /dev/null; then
                            git clone https://github.com/matteocervelli/op-env-manager.git /tmp/op-env-manager
                            sudo ln -s /tmp/op-env-manager/bin/op-env-manager /usr/local/bin/op-env-manager
                        fi
                        op-env-manager version
                    '''
                }
            }
        }

        stage('Test') {
            steps {
                sh '''
                    op-env-manager run \
                        --vault "$VAULT" \
                        --item "$ITEM" \
                        --section "test" \
                        -- npm test
                '''
            }
        }

        stage('Build') {
            steps {
                sh '''
                    op-env-manager run \
                        --vault "$VAULT" \
                        --item "$ITEM" \
                        --section "build" \
                        -- npm run build
                '''
            }
        }

        stage('Deploy') {
            when {
                branch 'main'
            }
            steps {
                script {
                    def section = env.BRANCH_NAME == 'main' ? 'production' : 'staging'
                    sh """
                        op-env-manager run \
                            --vault "$VAULT" \
                            --item "$ITEM" \
                            --section "$section" \
                            -- ./deploy.sh
                    """
                }
            }
        }
    }

    post {
        always {
            // Clean up any injected env files (if using inject instead of run)
            sh 'rm -f .env.* || true'
        }
    }
}
```

### Scripted Pipeline with Parameters

```groovy
// Jenkinsfile
properties([
    parameters([
        choice(
            name: 'ENVIRONMENT',
            choices: ['development', 'staging', 'production'],
            description: 'Deployment environment'
        ),
        string(
            name: 'VAULT',
            defaultValue: 'Production',
            description: '1Password vault name'
        )
    ])
])

node {
    stage('Checkout') {
        checkout scm
    }

    stage('Setup Tools') {
        sh '''
            # Install 1Password CLI
            if ! command -v op &> /dev/null; then
                curl -sSfLo op.zip https://cache.agilebits.com/dist/1P/op2/pkg/v2.23.0/op_linux_amd64_v2.23.0.zip
                unzip -o op.zip -d /usr/local/bin
                rm op.zip
            fi

            # Install op-env-manager
            git clone https://github.com/matteocervelli/op-env-manager.git /tmp/op-env-manager-$BUILD_NUMBER
            ln -s /tmp/op-env-manager-$BUILD_NUMBER/bin/op-env-manager /usr/local/bin/op-env-manager-$BUILD_NUMBER
        '''
    }

    stage('Deploy') {
        withCredentials([string(credentialsId: 'op-service-account-token', variable: 'OP_SERVICE_ACCOUNT_TOKEN')]) {
            sh """
                /usr/local/bin/op-env-manager-${BUILD_NUMBER} run \
                    --vault "${params.VAULT}" \
                    --item "myapp" \
                    --section "${params.ENVIRONMENT}" \
                    -- ./deploy.sh
            """
        }
    }

    stage('Cleanup') {
        sh """
            rm -rf /tmp/op-env-manager-${BUILD_NUMBER}
            rm -f /usr/local/bin/op-env-manager-${BUILD_NUMBER}
        """
    }
}
```

---

## CircleCI

### Basic Config

```yaml
# .circleci/config.yml
version: 2.1

executors:
  default:
    docker:
      - image: cimg/node:18.0

commands:
  setup_op_env_manager:
    steps:
      - run:
          name: Install 1Password CLI
          command: |
            curl -sSfLo op.zip https://cache.agilebits.com/dist/1P/op2/pkg/v2.23.0/op_linux_amd64_v2.23.0.zip
            sudo unzip -o op.zip -d /usr/local/bin
            rm op.zip
            op --version

      - run:
          name: Install op-env-manager
          command: |
            git clone https://github.com/matteocervelli/op-env-manager.git /tmp/op-env-manager
            sudo ln -s /tmp/op-env-manager/bin/op-env-manager /usr/local/bin/op-env-manager
            op-env-manager version

jobs:
  test:
    executor: default
    steps:
      - checkout
      - setup_op_env_manager
      - run:
          name: Run tests with secrets
          command: |
            op-env-manager run \
              --vault "Production" \
              --item "myapp" \
              --section "test" \
              -- npm test

  build:
    executor: default
    steps:
      - checkout
      - setup_op_env_manager
      - run:
          name: Build with secrets
          command: |
            op-env-manager run \
              --vault "Production" \
              --item "myapp" \
              --section "build" \
              -- npm run build
      - persist_to_workspace:
          root: .
          paths:
            - dist

  deploy:
    executor: default
    steps:
      - checkout
      - attach_workspace:
          at: .
      - setup_op_env_manager
      - run:
          name: Deploy to production
          command: |
            op-env-manager run \
              --vault "Production" \
              --item "myapp" \
              --section "production" \
              -- ./deploy.sh

workflows:
  version: 2
  test_build_deploy:
    jobs:
      - test
      - build:
          requires:
            - test
      - deploy:
          requires:
            - build
          filters:
            branches:
              only: main
```

---

## Best Practices

### Security

1. **Service Account Permissions**:
   ```bash
   # Grant minimal permissions
   # ✓ Read-only access to specific vaults
   # ✓ Separate service accounts per project
   # ✗ Avoid admin/full access
   ```

2. **Token Storage**:
   - Store `OP_SERVICE_ACCOUNT_TOKEN` as encrypted secret
   - Never log or print the token
   - Rotate tokens regularly (every 90 days)
   - Use different tokens per environment

3. **Audit Trail**:
   - Monitor 1Password activity logs
   - Set up alerts for unusual access patterns
   - Review service account usage monthly

### Performance

1. **Caching**:
   ```yaml
   # Cache op-env-manager installation
   - uses: actions/cache@v3
     with:
       path: /tmp/op-env-manager
       key: op-env-manager-v1
   ```

2. **Parallel Jobs**:
   ```yaml
   # Safe: Multiple read operations in parallel
   - name: Run tests (parallel safe)
     run: |
       op-env-manager run --vault "Prod" --item "app1" -- npm test &
       op-env-manager run --vault "Prod" --item "app2" -- npm test &
       wait
   ```

3. **Use `run` Command**:
   ```bash
   # ✓ Prefer run (no temp files, faster)
   op-env-manager run --vault "Prod" --item "app" -- command

   # ✗ Avoid inject in CI (slower, temp files)
   op-env-manager inject --vault "Prod" --output .env
   source .env
   ```

### Reliability

1. **Dry-Run Testing**:
   ```yaml
   - name: Validate secrets exist
     run: |
       op-env-manager inject --vault "Prod" --item "app" --dry-run
   ```

2. **Error Handling**:
   ```yaml
   - name: Deploy with error handling
     run: |
       set -e
       if ! op-env-manager run --vault "Prod" --item "app" -- ./deploy.sh; then
         echo "Deployment failed - check 1Password access"
         exit 1
       fi
   ```

3. **Fallback Strategy**:
   ```yaml
   - name: Deploy with fallback
     run: |
       # Try primary vault, fallback to backup
       op-env-manager run --vault "Production" --item "app" -- ./deploy.sh || \
       op-env-manager run --vault "ProductionBackup" --item "app" -- ./deploy.sh
   ```

### Debugging

1. **Verbose Logging**:
   ```bash
   # Enable 1Password CLI debug mode
   export OP_DEBUG=1
   op account list
   ```

2. **Test Locally**:
   ```bash
   # Simulate CI environment
   export OP_SERVICE_ACCOUNT_TOKEN="your-token"
   op-env-manager run --vault "Prod" --item "app" -- env | grep API_KEY
   ```

3. **Validate Setup**:
   ```yaml
   - name: Validate 1Password setup
     run: |
       op --version
       op-env-manager version
       op account list
       op vault list
   ```

---

## Troubleshooting

### Common Issues

**"Not signed in to 1Password CLI"**:
```yaml
# Ensure OP_SERVICE_ACCOUNT_TOKEN is set
env:
  OP_SERVICE_ACCOUNT_TOKEN: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}
```

**"Vault not found"**:
```bash
# Vault names are case-sensitive
# Check service account has access to vault
op vault list
```

**"Item not found"**:
```bash
# Ensure item exists and service account has access
op item list --vault "Production" --tags "op-env-manager"
```

**Network timeouts**:
```yaml
# Add retry logic
- name: Deploy with retry
  run: |
    for i in 1 2 3; do
      op-env-manager run --vault "Prod" --item "app" -- ./deploy.sh && break
      echo "Attempt $i failed, retrying..."
      sleep 5
    done
```

---

## Next Steps

- Read [TEAM_COLLABORATION.md](TEAM_COLLABORATION.md) for team workflows
- See [QUICKSTART.md](QUICKSTART.md) for local development patterns
- Review [1PASSWORD_SETUP.md](1PASSWORD_SETUP.md) for service account setup

---

**Questions or issues?** [Open an issue](https://github.com/matteocervelli/op-env-manager/issues) or [start a discussion](https://github.com/matteocervelli/op-env-manager/discussions).
