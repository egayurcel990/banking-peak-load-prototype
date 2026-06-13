package memory

import (
	"context"
	"fmt"
	"sync"

	"github.com/marquisccel/banking-peak-load-prototype/internal/domain/transaction"
)

type TransactionRepository struct {
	mu   sync.RWMutex
	data map[string]transaction.Transaction
}

func NewTransactionRepository() *TransactionRepository {
	return &TransactionRepository{
		data: make(map[string]transaction.Transaction),
	}
}

func (r *TransactionRepository) Save(_ context.Context, tx *transaction.Transaction) error {
	r.mu.Lock()
	r.data[tx.ID] = *tx
	r.mu.Unlock()

	return nil
}

func (r *TransactionRepository) GetByID(_ context.Context, id string) (*transaction.Transaction, error) {
	r.mu.RLock()
	tx, ok := r.data[id]
	r.mu.RUnlock()
	if !ok {
		return nil, fmt.Errorf("transaction %s not found", id)
	}

	return &tx, nil
}

func (r *TransactionRepository) UpdateStatus(ctx context.Context, id string, status transaction.Status) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	tx, ok := r.data[id]
	if !ok {
		return fmt.Errorf("transaction %s not found", id)
	}
	tx.Status = status
	r.data[id] = tx
	return nil
}
