# Go Backend API - OAuth Authentication

Create a Go backend API with PostgreSQL for OAuth authentication following 12-factor app principles.

## Requirements

1. **OAuth Authentication**
   - Google and Apple OAuth endpoints that handle sign-in and create/retrieve users

2. **User Model**
   - email
   - name
   - profile_picture
   - provider
   - provider_id
   - timestamps

3. **JWT Token Generation**
   - For authenticated sessions

4. **Database Migrations**
   - User table setup

5. **Environment Configuration**
   - All configuration via environment variables
   - No hardcoded secrets

6. **12-Factor App Compliance**
   - Stateless design
   - Proper logging to stdout

7. **Project Structure**
   - Clean separation: handlers, models, middleware

8. **Deployment**
   - Railway deployment-ready
   - Docker support