# Crypto Paper Trading App - Development Plan

## Tech Stack
- **Frontend**: React Native (Expo)
- **Backend**: Golang (Fiber/Gin framework)
- **Database**: PostgreSQL
- **Integrations**: 
  - CCXT (crypto exchange data)
  - Stripe (payments)
  - Google OAuth (authentication)
  - Claude API (trade analysis)

## Project Structure
```
crypto-paper-trader/
├── backend/
│   ├── cmd/
│   │   └── api/
│   │       └── main.go
│   ├── internal/
│   │   ├── auth/
│   │   ├── trades/
│   │   ├── payments/
│   │   ├── analysis/
│   │   └── database/
│   ├── migrations/
│   ├── Dockerfile
│   └── go.mod
├── mobile/
│   ├── src/
│   │   ├── screens/
│   │   ├── components/
│   │   ├── api/
│   │   └── navigation/
│   ├── app.json
│   └── package.json
├── database/
│   └── schema.sql
├── .github/
│   └── workflows/
│       ├── backend-deploy.yml
│       └── mobile-deploy.yml
├── docker-compose.yml
├── .env.example
└── README.md
```

---

## Phase 1: Database & Backend Foundation (4-5 hours)

### 1.1 Database Schema

**PostgreSQL Tables:**

```sql
-- users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    oauth_provider VARCHAR(50) NOT NULL,
    oauth_id VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- trades table
CREATE TABLE trades (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    symbol VARCHAR(20) NOT NULL,
    exchange VARCHAR(50) NOT NULL,
    entry_price DECIMAL(20, 8) NOT NULL,
    exit_price DECIMAL(20, 8),
    quantity DECIMAL(20, 8) NOT NULL,
    side VARCHAR(10) NOT NULL, -- 'long' or 'short'
    status VARCHAR(20) DEFAULT 'open', -- 'open', 'closed'
    pnl DECIMAL(20, 8),
    pnl_percent DECIMAL(10, 4),
    notes TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    closed_at TIMESTAMP,
    INDEX idx_user_trades (user_id, created_at),
    INDEX idx_status (status)
);

-- subscriptions table
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    stripe_customer_id VARCHAR(255) UNIQUE NOT NULL,
    stripe_subscription_id VARCHAR(255),
    status VARCHAR(20) DEFAULT 'inactive', -- 'active', 'inactive', 'cancelled'
    plan_type VARCHAR(50), -- 'basic', 'pro', etc.
    current_period_end TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

### 1.2 Golang Backend API Endpoints

**Authentication:**
- `POST /api/v1/auth/google` - OAuth callback handler
- `POST /api/v1/auth/refresh` - Refresh JWT token
- `GET /api/v1/auth/me` - Get current user info

**Trades:**
- `GET /api/v1/trades` - List user's trades (with pagination, filters)
- `POST /api/v1/trades` - Create new trade
- `GET /api/v1/trades/:id` - Get single trade details
- `PUT /api/v1/trades/:id/close` - Close an open trade
- `DELETE /api/v1/trades/:id` - Delete a trade

**Market Data:**
- `GET /api/v1/prices/:symbol` - Get current price for symbol
- `GET /api/v1/exchanges` - List supported exchanges

**Analysis:**
- `POST /api/v1/analyze` - Send closed trades to Claude API for analysis
- `GET /api/v1/stats` - Get user trading stats (win rate, avg P&L, etc.)

**Payments:**
- `POST /api/v1/payments/create-checkout` - Create Stripe checkout session
- `POST /api/v1/webhooks/stripe` - Handle Stripe webhooks
- `GET /api/v1/subscription` - Get current subscription status

### 1.3 Backend Implementation Details

**Required Go Packages:**
```go
github.com/gofiber/fiber/v2
github.com/golang-jwt/jwt/v5
github.com/lib/pq
github.com/stripe/stripe-go/v76
github.com/ccxt/ccxt
google.golang.org/api/oauth2/v2
github.com/joho/godotenv
```

**Middleware:**
- JWT authentication middleware
- CORS middleware
- Rate limiting middleware
- Request logging middleware

**Environment Variables (.env):**
```
DATABASE_URL=postgresql://user:password@localhost:5432/crypto_trader
JWT_SECRET=your-jwt-secret
GOOGLE_CLIENT_ID=your-google-client-id
GOOGLE_CLIENT_SECRET=your-google-client-secret
STRIPE_SECRET_KEY=your-stripe-secret
CLAUDE_API_KEY=your-claude-api-key
PORT=8080
ENVIRONMENT=development
```

---

## Phase 2: React Native Mobile App (3-4 hours)

### 2.1 App Screens

**LoginScreen:**
- Google OAuth button
- App branding/logo
- Terms & privacy links

**HomeScreen (Dashboard):**
- Active trades list (card view)
- Portfolio P&L summary
- Quick stats (win rate, total trades)
- "New Trade" FAB button

**NewTradeScreen:**
- Exchange selector dropdown
- Symbol input (autocomplete)
- Entry price input
- Quantity input
- Side selector (Long/Short)
- Optional notes field
- "Create Trade" button

**TradeDetailScreen:**
- Trade info (symbol, entry, current price, P&L)
- Live price updates
- "Close Trade" button
- Edit notes
- Delete trade option

**TradesHistoryScreen:**
- List of closed trades
- Filter by date, symbol, profit/loss
- Export trades button

**AnalysisScreen:**
- "Analyze My Trades" button
- AI-generated insights display
- Trading patterns
- Recommendations

**SettingsScreen:**
- Subscription status
- "Upgrade" button
- Logout

### 2.2 React Native Dependencies

```json
{
  "dependencies": {
    "expo": "~50.0.0",
    "react-native": "0.73.0",
    "@react-navigation/native": "^6.1.0",
    "@react-navigation/stack": "^6.3.0",
    "axios": "^1.6.0",
    "@react-native-async-storage/async-storage": "^1.21.0",
    "react-native-dotenv": "^3.4.0",
    "@expo/vector-icons": "^14.0.0",
    "react-native-paper": "^5.11.0",
    "react-native-chart-kit": "^6.12.0",
    "@stripe/stripe-react-native": "^0.35.0"
  }
}
```

### 2.3 API Client Setup

**api/client.js:**
```javascript
import axios from 'axios';
import AsyncStorage from '@react-native-async-storage/async-storage';

const API_URL = process.env.API_URL || 'http://localhost:8080/api/v1';

const apiClient = axios.create({
  baseURL: API_URL,
  timeout: 10000,
});

// Add auth token to requests
apiClient.interceptors.request.use(async (config) => {
  const token = await AsyncStorage.getItem('authToken');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// Handle token refresh on 401
apiClient.interceptors.response.use(
  (response) => response,
  async (error) => {
    if (error.response?.status === 401) {
      // Handle logout or token refresh
      await AsyncStorage.removeItem('authToken');
      // Navigate to login
    }
    return Promise.reject(error);
  }
);

export default apiClient;
```

### 2.4 State Management

Use React Context API for:
- Auth state (user, token)
- Active trades
- Subscription status

---

## Phase 3: Integrations (3-4 hours)

### 3.1 Google OAuth Integration

**Backend (Golang):**
```go
// Verify Google token and create/find user
func handleGoogleLogin(c *fiber.Ctx) error {
    token := c.FormValue("token")
    
    // Verify token with Google
    payload, err := verifyGoogleToken(token)
    if err != nil {
        return c.Status(401).JSON(fiber.Map{"error": "Invalid token"})
    }
    
    // Find or create user
    user, err := findOrCreateUser(payload.Email, "google", payload.Sub)
    
    // Generate JWT
    jwtToken := generateJWT(user.ID)
    
    return c.JSON(fiber.Map{
        "token": jwtToken,
        "user": user,
    })
}
```

**Frontend (React Native):**
```javascript
import * as Google from 'expo-auth-session/providers/google';

const [request, response, promptAsync] = Google.useAuthRequest({
  expoClientId: 'YOUR_EXPO_CLIENT_ID',
  androidClientId: 'YOUR_ANDROID_CLIENT_ID',
  iosClientId: 'YOUR_IOS_CLIENT_ID',
});

// Handle response and send to backend
```

### 3.2 CCXT Integration (Backend)

```go
import "github.com/ccxt/ccxt/go"

func getCurrentPrice(exchange, symbol string) (float64, error) {
    ex := ccxt.NewBinance() // or other exchanges
    
    ticker, err := ex.FetchTicker(symbol)
    if err != nil {
        return 0, err
    }
    
    return ticker.Last, nil
}
```

### 3.3 Stripe Integration

**Backend Webhook Handler:**
```go
func handleStripeWebhook(c *fiber.Ctx) error {
    payload := c.Body()
    sig := c.Get("Stripe-Signature")
    
    event, err := webhook.ConstructEvent(payload, sig, webhookSecret)
    if err != nil {
        return c.Status(400).SendString("Invalid signature")
    }
    
    switch event.Type {
    case "customer.subscription.created":
        // Update user subscription status
    case "customer.subscription.deleted":
        // Cancel user subscription
    }
    
    return c.SendStatus(200)
}
```

**Frontend (React Native):**
```javascript
import { useStripe } from '@stripe/stripe-react-native';

const { initPaymentSheet, presentPaymentSheet } = useStripe();

// Create checkout session via API, then:
await initPaymentSheet({
  merchantDisplayName: "Crypto Paper Trader",
  customerId: customerId,
  customerEphemeralKeySecret: ephemeralKey,
  paymentIntentClientSecret: paymentIntent,
});

const { error } = await presentPaymentSheet();
```

### 3.4 Claude API Integration

**Backend Analysis Endpoint:**
```go
func analyzeTrades(c *fiber.Ctx) error {
    userID := c.Locals("userID").(string)
    
    trades, err := getClosedTrades(userID)
    if err != nil {
        return c.Status(500).JSON(fiber.Map{"error": "Failed to fetch trades"})
    }
    
    // Format trades for Claude
    prompt := formatTradesForAnalysis(trades)
    
    // Call Claude API
    analysis, err := callClaudeAPI(prompt)
    if err != nil {
        return c.Status(500).JSON(fiber.Map{"error": "Analysis failed"})
    }
    
    return c.JSON(fiber.Map{"analysis": analysis})
}

func formatTradesForAnalysis(trades []Trade) string {
    return fmt.Sprintf(`Analyze these paper trades and provide insights:
    
Total trades: %d
Win rate: %.2f%%
Average profit: %.2f%%

Trade details:
%s

Provide:
1. Pattern analysis (what works/doesn't work)
2. Common mistakes
3. Recommendations for improvement
`, len(trades), calculateWinRate(trades), calculateAvgProfit(trades), formatTradeList(trades))
}
```

---

## Phase 4: GitHub Actions CI/CD (2-3 hours)

### 4.1 Backend Deployment

**.github/workflows/backend-deploy.yml:**
```yaml
name: Deploy Backend

on:
  push:
    branches:
      - main
      - develop
    paths:
      - 'backend/**'

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}/backend

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2

      - name: Log in to Container Registry
        uses: docker/login-action@v2
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v4
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=sha

      - name: Build and push Docker image
        uses: docker/build-push-action@v4
        with:
          context: ./backend
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Deploy to Production
        if: github.ref == 'refs/heads/main'
        run: |
          # SSH into server and pull new image
          # Or use cloud provider CLI (AWS/DO/GCP)
        env:
          SSH_PRIVATE_KEY: ${{ secrets.SSH_PRIVATE_KEY }}
          PROD_HOST: ${{ secrets.PROD_HOST }}

      - name: Deploy to Staging
        if: github.ref == 'refs/heads/develop'
        run: |
          # Deploy to staging environment
        env:
          STAGING_HOST: ${{ secrets.STAGING_HOST }}

      - name: Run Database Migrations
        run: |
          # Run migrations after deployment
```

### 4.2 Mobile App Deployment

**.github/workflows/mobile-deploy.yml:**
```yaml
name: Deploy Mobile App

on:
  push:
    branches:
      - main
      - develop
    paths:
      - 'mobile/**'

jobs:
  build-ios:
    runs-on: macos-latest
    if: github.ref == 'refs/heads/main'
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Setup Node
        uses: actions/setup-node@v3
        with:
          node-version: 18

      - name: Install dependencies
        working-directory: ./mobile
        run: npm ci

      - name: Install EAS CLI
        run: npm install -g eas-cli

      - name: Build iOS
        working-directory: ./mobile
        run: eas build --platform ios --profile production --non-interactive
        env:
          EXPO_TOKEN: ${{ secrets.EXPO_TOKEN }}

      - name: Submit to TestFlight
        working-directory: ./mobile
        run: eas submit -p ios --latest
        env:
          EXPO_TOKEN: ${{ secrets.EXPO_TOKEN }}

  build-android:
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Setup Node
        uses: actions/setup-node@v3
        with:
          node-version: 18

      - name: Install dependencies
        working-directory: ./mobile
        run: npm ci

      - name: Install EAS CLI
        run: npm install -g eas-cli

      - name: Build Android
        working-directory: ./mobile
        run: eas build --platform android --profile production --non-interactive
        env:
          EXPO_TOKEN: ${{ secrets.EXPO_TOKEN }}

      - name: Submit to Play Console
        working-directory: ./mobile
        run: eas submit -p android --latest
        env:
          EXPO_TOKEN: ${{ secrets.EXPO_TOKEN }}

  build-staging:
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/develop'
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Setup Node
        uses: actions/setup-node@v3
        with:
          node-version: 18

      - name: Install dependencies
        working-directory: ./mobile
        run: npm ci

      - name: Install EAS CLI
        run: npm install -g eas-cli

      - name: Build Preview
        working-directory: ./mobile
        run: eas build --platform all --profile preview --non-interactive
        env:
          EXPO_TOKEN: ${{ secrets.EXPO_TOKEN }}
```

### 4.3 Required GitHub Secrets

**Backend Secrets:**
- `SSH_PRIVATE_KEY` - SSH key for server deployment
- `PROD_HOST` - Production server hostname
- `STAGING_HOST` - Staging server hostname
- `DATABASE_URL_PROD` - Production database connection string
- `DATABASE_URL_STAGING` - Staging database connection string
- `STRIPE_SECRET_KEY` - Stripe API key
- `CLAUDE_API_KEY` - Claude API key
- `GOOGLE_CLIENT_SECRET` - Google OAuth secret

**Mobile Secrets:**
- `EXPO_TOKEN` - Expo access token for EAS builds
- `APPLE_ID` - Apple Developer ID (for iOS submission)
- `APPLE_APP_SPECIFIC_PASSWORD` - App-specific password
- `GOOGLE_SERVICE_ACCOUNT_KEY` - Google Play service account (for Android)

---

## Phase 5: Testing & Polish (2-3 hours)

### 5.1 Backend Testing

**Unit Tests:**
- Test trade creation logic
- Test P&L calculations
- Test JWT generation/validation
- Test database operations

**Integration Tests:**
- Test API endpoints with real database
- Test OAuth flow
- Test Stripe webhooks
- Test CCXT price fetching

### 5.2 Mobile Testing

**Component Tests:**
- Test trade creation form validation
- Test P&L display calculations
- Test error handling

**E2E Tests:**
- Complete user flow: login → create trade → close trade → view analysis
- Test offline behavior
- Test payment flow

### 5.3 Error Handling

**Backend:**
- Proper HTTP status codes
- Consistent error response format
- Logging and monitoring
- Rate limiting

**Mobile:**
- Loading states for all async operations
- Error messages for failed API calls
- Retry mechanisms
- Offline indicators

---

## Development Timeline

**Total: 14-19 hours**

1. **Database & Backend API** (4-5 hours)
   - Schema design
   - API endpoints
   - Authentication
   - Testing

2. **React Native UI** (3-4 hours)
   - Screen layouts
   - Navigation
   - API integration
   - State management

3. **Integrations** (3-4 hours)
   - OAuth
   - CCXT
   - Stripe
   - Claude API

4. **CI/CD Setup** (2-3 hours)
   - GitHub Actions
   - Environment configs
   - Deployment scripts

5. **Testing & Polish** (2-3 hours)
   - Unit tests
   - E2E tests
   - Bug fixes
   - UI improvements

---

## Local Development Setup

### Prerequisites
- Go 1.21+
- Node.js 18+
- Docker & Docker Compose
- PostgreSQL 15+
- Expo CLI
- iOS Simulator / Android Emulator

### Quick Start

```bash
# Clone repo
git clone <repo-url>
cd crypto-paper-trader

# Start database
docker-compose up -d postgres

# Run backend
cd backend
cp .env.example .env
# Edit .env with your API keys
go mod download
go run cmd/api/main.go

# Run mobile app (in new terminal)
cd mobile
npm install
cp .env.example .env
# Edit .env with your API URL
npx expo start
```

### Docker Compose

**docker-compose.yml:**
```yaml
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: crypto_trader
      POSTGRES_PASSWORD: dev_password
      POSTGRES_DB: crypto_trader_dev
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./database/schema.sql:/docker-entrypoint-initdb.d/schema.sql

  backend:
    build: ./backend
    ports:
      - "8080:8080"
    depends_on:
      - postgres
    environment:
      DATABASE_URL: postgresql://crypto_trader:dev_password@postgres:5432/crypto_trader_dev
      JWT_SECRET: dev-secret-key
      PORT: 8080
    volumes:
      - ./backend:/app
    command: go run cmd/api/main.go

volumes:
  postgres_data:
```

---

## Production Deployment Checklist

### Backend
- [ ] Environment variables configured
- [ ] Database migrations run
- [ ] SSL certificates installed
- [ ] Rate limiting configured
- [ ] Logging/monitoring setup (e.g., Sentry)
- [ ] Backup strategy implemented
- [ ] CORS properly configured
- [ ] API documentation published

### Mobile
- [ ] App icons and splash screens
- [ ] Privacy policy and terms of service
- [ ] App Store/Play Store metadata
- [ ] Push notification certificates
- [ ] Analytics setup (optional)
- [ ] Crash reporting (e.g., Sentry)
- [ ] Over-the-air updates configured (Expo Updates)

### Infrastructure
- [ ] Domain name and DNS configured
- [ ] CDN setup (if needed)
- [ ] Database backups automated
- [ ] Server monitoring
- [ ] Load balancing (if needed)
- [ ] Secrets management

---

## Next Steps After MVP

1. **Real-time price updates** - WebSocket connection for live prices
2. **Advanced charting** - TradingView integration
3. **Social features** - Share trades, leaderboards
4. **Advanced analytics** - More detailed AI insights
5. **Portfolio management** - Multiple portfolios
6. **Trading strategies** - Backtest strategies
7. **Notifications** - Price alerts, trade reminders
8. **Export/Import** - CSV export, import from real exchanges

---

## Resources & Documentation

**Backend:**
- [Fiber Framework](https://gofiber.io/)
- [CCXT Documentation](https://docs.ccxt.com/)
- [Stripe API](https://stripe.com/docs/api)
- [Claude API](https://docs.anthropic.com/)

**Mobile:**
- [React Native](https://reactnative.dev/)
- [Expo](https://docs.expo.dev/)
- [React Navigation](https://reactnavigation.org/)
- [Stripe React Native](https://stripe.com/docs/payments/accept-a-payment?platform=react-native)

**DevOps:**
- [GitHub Actions](https://docs.github.com/en/actions)
- [Docker](https://docs.docker.com/)
- [EAS Build](https://docs.expo.dev/build/introduction/)