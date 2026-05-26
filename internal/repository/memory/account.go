package memory

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/egayurcel990/banking-peak-load-prototype/internal/domain/account"
)

type AccountRepository struct {
	mu   sync.RWMutex
	data map[int64]account.Account
}

func NewAccountRepository() *AccountRepository {
	now := time.Now()
	return &AccountRepository{
		data: map[int64]account.Account{
			1001: {ID: 1001, Name: "Budi Santoso", Balance: 10_000_000, UpdatedAt: now},
			1002: {ID: 1002, Name: "Siti Rahayu", Balance: 25_000_000, UpdatedAt: now},
			1003: {ID: 1003, Name: "Agus Wijaya", Balance: 5_000_000, UpdatedAt: now},
			1004: {ID: 1004, Name: "Dewi Lestari", Balance: 50_000_000, UpdatedAt: now},
			1005: {ID: 1005, Name: "Rudi Hartono", Balance: 1_000_000, UpdatedAt: now},
		},
	}
}

func (r *AccountRepository) GetByID(_ context.Context, id int64) (*account.Account, error) {
	r.mu.RLock()
	a, ok := r.data[id]
	r.mu.RUnlock()
	if !ok {
		return nil, fmt.Errorf("account %d not found", id)
	}
	return &a, nil
}
