# Contributing to EvoAuth Service

Thank you for your interest in contributing to EvoAuth Service! We welcome contributions from everyone and are grateful for every contribution, no matter how small.

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [How to Contribute](#how-to-contribute)
- [Coding Standards](#coding-standards)
- [Testing Guidelines](#testing-guidelines)
- [Documentation](#documentation)
- [Pull Request Process](#pull-request-process)
- [Issue Reporting](#issue-reporting)
- [Community](#community)

## 📜 Code of Conduct

This project and everyone participating in it is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code. Please report unacceptable behavior to [conduct@evo-auth-service.com](mailto:conduct@evo-auth-service.com).

## 🚀 Getting Started

### Prerequisites

Before you begin, ensure you have the following installed:

- **Ruby 3.4.4+** (we recommend using [rbenv](https://github.com/rbenv/rbenv) or [RVM](https://rvm.io/))
- **Rails 7.1+**
- **PostgreSQL 12+**
- **Redis 6+**
- **Git**

### Development Setup

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/evo-auth-service.git
   cd evo-auth-service
   ```

3. **Add the upstream remote**:
   ```bash
   git remote add upstream https://github.com/EvolutionAPI/evo-auth-service.git
   ```

4. **Install dependencies**:
   ```bash
   bundle install
   ```

5. **Setup the database**:
   ```bash
   cp .env.example .env
   # Edit .env with your database credentials
   rails db:create
   rails db:migrate
   rails db:seed
   ```

6. **Run the tests** to ensure everything is working:
   ```bash
   bundle exec rspec
   ```

7. **Start the development server**:
   ```bash
   rails server -p 3001
   ```

## 🤝 How to Contribute

### Types of Contributions

We welcome several types of contributions:

- **🐛 Bug Reports**: Help us identify and fix issues
- **✨ Feature Requests**: Suggest new features or improvements
- **📝 Documentation**: Improve or add documentation
- **🧪 Tests**: Add or improve test coverage
- **🔧 Code**: Fix bugs or implement new features
- **🌍 Translations**: Add support for new languages

### Contribution Workflow

1. **Check existing issues** to see if your contribution is already being worked on
2. **Create an issue** for new features or bugs (if one doesn't exist)
3. **Fork the repository** and create a feature branch
4. **Make your changes** following our coding standards
5. **Add tests** for your changes
6. **Update documentation** if necessary
7. **Submit a pull request**

## 💻 Development Workflow

### Branch Naming Convention

Use descriptive branch names with prefixes:

- `feature/add-webhook-support`
- `bugfix/fix-oauth-token-refresh`
- `docs/update-api-documentation`
- `test/add-mfa-integration-tests`
- `refactor/improve-rbac-performance`

### Commit Message Format

We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

**Types:**
- `feat`: A new feature
- `fix`: A bug fix
- `docs`: Documentation only changes
- `style`: Changes that do not affect the meaning of the code
- `refactor`: A code change that neither fixes a bug nor adds a feature
- `test`: Adding missing tests or correcting existing tests
- `chore`: Changes to the build process or auxiliary tools

**Examples:**
```
feat(auth): add support for WebAuthn MFA
fix(oauth): resolve token refresh race condition
docs(api): update authentication examples
test(rbac): add integration tests for role assignment
```

## 🎨 Coding Standards

### Ruby Style Guide

We follow the [Ruby Style Guide](https://rubystyle.guide/) with some project-specific conventions:

- **Line Length**: Maximum 150 characters (configured in `.rubocop.yml`)
- **Method Length**: Maximum 19 lines
- **Class Length**: Maximum 175 lines
- **Indentation**: 2 spaces, no tabs
- **String Literals**: Prefer single quotes unless interpolation is needed

### Code Quality Tools

We use several tools to maintain code quality:

```bash
# Run RuboCop for style checking
bundle exec rubocop

# Auto-fix style issues
bundle exec rubocop -a

# Run Brakeman for security analysis
bundle exec brakeman

# Run bundle-audit for dependency vulnerabilities
bundle exec bundle-audit check --update
```

### Rails Conventions

- **Controllers**: Keep them thin, delegate business logic to services
- **Models**: Use for data validation and associations only
- **Services**: Place business logic in `app/services/`
- **Concerns**: Extract common functionality into concerns
- **Database**: Always use migrations for schema changes

### Security Guidelines

- **Input Validation**: Always validate and sanitize user input
- **SQL Injection**: Use ActiveRecord methods, avoid raw SQL
- **Authentication**: Use existing authentication mechanisms
- **Authorization**: Check permissions for all actions
- **Sensitive Data**: Never log passwords or tokens
- **Dependencies**: Keep dependencies up to date

## 🧪 Testing Guidelines

### Test Structure

We use RSpec for testing with the following structure:

```
spec/
├── models/           # Unit tests for models
├── controllers/      # Controller tests
├── requests/         # API integration tests
├── services/         # Service object tests
├── factories/        # FactoryBot factories
├── support/          # Test helpers and shared examples
└── fixtures/         # Test data files
```

### Writing Tests

- **Unit Tests**: Test individual methods and classes in isolation
- **Integration Tests**: Test API endpoints and user workflows
- **Feature Tests**: Test complete user journeys
- **Security Tests**: Test authentication and authorization

### Test Requirements

- **Coverage**: Maintain 95%+ test coverage
- **Performance**: Tests should run quickly (< 5 minutes for full suite)
- **Reliability**: Tests should be deterministic and not flaky
- **Clarity**: Test names should clearly describe what is being tested

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/models/user_spec.rb

# Run tests with coverage
COVERAGE=true bundle exec rspec

# Run tests matching a pattern
bundle exec rspec --tag auth

# Run tests in parallel (faster)
bundle exec parallel_rspec spec/
```

## 📚 Documentation

### API Documentation

- **Swagger/OpenAPI**: Update `spec/swagger_helper.rb` and request specs
- **Inline Comments**: Document complex business logic
- **README**: Update feature lists and examples

### Code Documentation

- **YARD**: Use YARD syntax for method documentation
- **Comments**: Explain "why" not "what"
- **Examples**: Provide usage examples for complex methods

### Documentation Standards

```ruby
# Good: Explains the business logic
# Generates a secure random token for MFA backup codes
# and ensures it doesn't conflict with existing codes
def generate_backup_code
  # implementation
end

# Bad: States the obvious
# This method generates a backup code
def generate_backup_code
  # implementation
end
```

## 🔄 Pull Request Process

### Before Submitting

1. **Sync with upstream**:
   ```bash
   git fetch upstream
   git checkout main
   git merge upstream/main
   ```

2. **Rebase your feature branch**:
   ```bash
   git checkout feature/your-feature
   git rebase main
   ```

3. **Run the full test suite**:
   ```bash
   bundle exec rspec
   bundle exec rubocop
   ```

4. **Update documentation** if necessary

### Pull Request Template

When creating a pull request, please include:

- **Description**: Clear description of what the PR does
- **Motivation**: Why is this change needed?
- **Testing**: How was this tested?
- **Screenshots**: For UI changes (if applicable)
- **Breaking Changes**: Any breaking changes?
- **Checklist**: Use our PR template checklist

### Review Process

1. **Automated Checks**: CI/CD pipeline runs tests and quality checks
2. **Code Review**: At least one maintainer reviews the code
3. **Testing**: Reviewer tests the changes locally if needed
4. **Approval**: PR is approved and merged by a maintainer

### Merge Requirements

- ✅ All tests pass
- ✅ Code style checks pass
- ✅ Security scans pass
- ✅ At least one approving review
- ✅ Documentation updated (if needed)
- ✅ No merge conflicts

## 🐛 Issue Reporting

### Bug Reports

When reporting bugs, please include:

- **Environment**: Ruby version, Rails version, OS
- **Steps to Reproduce**: Clear steps to reproduce the issue
- **Expected Behavior**: What should happen
- **Actual Behavior**: What actually happens
- **Error Messages**: Full error messages and stack traces
- **Additional Context**: Any other relevant information

### Feature Requests

For feature requests, please include:

- **Problem**: What problem does this solve?
- **Solution**: Describe your proposed solution
- **Alternatives**: Any alternative solutions considered
- **Use Cases**: Real-world use cases for this feature
- **Implementation**: Any implementation ideas

### Issue Labels

We use labels to categorize issues:

- `bug`: Something isn't working
- `enhancement`: New feature or request
- `documentation`: Improvements or additions to documentation
- `good first issue`: Good for newcomers
- `help wanted`: Extra attention is needed
- `security`: Security-related issue
- `performance`: Performance improvement
- `breaking change`: Introduces breaking changes

## 🌟 Recognition

### Contributors

All contributors are recognized in our:

- **README.md**: Contributors section
- **CHANGELOG.md**: Release notes
- **GitHub**: Contributors graph

### Contribution Types

We recognize all types of contributions:

- 💻 Code
- 📖 Documentation
- 🐛 Bug reports
- 💡 Ideas
- 🤔 Answering questions
- ⚠️ Tests
- 🌍 Translation

## 🏆 Becoming a Maintainer

Regular contributors may be invited to become maintainers. Maintainers have:

- **Commit Access**: Can merge pull requests
- **Issue Triage**: Can label and close issues
- **Release Management**: Can create releases
- **Community Leadership**: Help guide the project direction

### Maintainer Responsibilities

- **Code Review**: Review and approve pull requests
- **Issue Management**: Triage and respond to issues
- **Community**: Help newcomers and answer questions
- **Quality**: Maintain code quality and test coverage
- **Security**: Respond to security issues promptly

## 💬 Community

### Communication Channels

- **GitHub Issues**: Bug reports and feature requests
- **GitHub Discussions**: General discussions and questions
- **Email**: [community@evo-auth-service.com](mailto:community@evo-auth-service.com)

### Getting Help

- **Documentation**: Check the [README](README.md) and [API docs](http://localhost:3001/api-docs)
- **Search Issues**: Look for existing issues and discussions
- **Ask Questions**: Create a GitHub discussion
- **Stack Overflow**: Tag questions with `evo-auth-service`

## 📞 Contact

- **General Questions**: [community@evo-auth-service.com](mailto:community@evo-auth-service.com)
- **Security Issues**: [security@evo-auth-service.com](mailto:security@evo-auth-service.com)
- **Code of Conduct**: [conduct@evo-auth-service.com](mailto:conduct@evo-auth-service.com)

---

Thank you for contributing to EvoAuth Service! 🎉

Your contributions help make authentication and authorization better for everyone.
