package service

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/egayurcel990/banking-peak-load-prototype/internal/domain/account"
	"github.com/egayurcel990/banking-peak-load-prototype/internal/logger"
	"github.com/egayurcel990/banking-peak-load-prototype/internal/metrics"
	"github.com/redis/go-redis/v9"
)

type AccountService interface {
	GetBalance(ctx context.Context, id int64) (*account.Account, error)
}

type accountService struct {
	repo       account.Repository
	redis      *redis.Client // nil → no caching
	balanceTTL time.Duration
}

func NewAccountService(repo account.Repository, rdb *redis.Client, balanceTTL time.Duration) AccountService {
	return &accountService{repo: repo, redis: rdb, balanceTTL: balanceTTL}
}

func (s *accountService) GetBalance(ctx context.Context, id int64) (*account.Account, error) {
	logger.Set(ctx, "account_id", id)

	if s.redis != nil {
		key := fmt.Sprintf("balance:%d", id)
		if cached, err := s.redis.Get(ctx, key).Bytes(); err == nil {
			var acc account.Account
			if err := json.Unmarshal(cached, &acc); err == nil {
				logger.Set(ctx, "cache_hit", true)
				logger.Set(ctx, "account_balance", acc.Balance)
				metrics.CacheHits.WithLabelValues("balance").Inc()
				return &acc, nil
			}
		}
		metrics.CacheMisses.WithLabelValues("balance").Inc()
		logger.Set(ctx, "cache_hit", false)
	}

	acc, err := s.repo.GetByID(ctx, id)
	if err != nil {
		logger.Set(ctx, "account_error", err.Error())
		return nil, err
	}

	if s.redis != nil {
		key := fmt.Sprintf("balance:%d", id)
		if data, err := json.Marshal(acc); err == nil {
			s.redis.Set(ctx, key, data, s.balanceTTL)
		}
	}

	logger.Set(ctx, "account_balance", acc.Balance)
	return acc, nil
}
