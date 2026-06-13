package worker

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/marquisccel/banking-peak-load-prototype/internal/domain/transaction"
	"github.com/marquisccel/banking-peak-load-prototype/internal/infrastructure/queue"
	"github.com/marquisccel/banking-peak-load-prototype/internal/logger"
	"github.com/marquisccel/banking-peak-load-prototype/internal/service"
	amqp "github.com/rabbitmq/amqp091-go"

	"github.com/jmoiron/sqlx"
	"github.com/redis/go-redis/v9"
)

type Worker struct {
	db    *sqlx.DB
	queue *queue.Client
	redis *redis.Client
	repo  transaction.Repository
}

func NewWorker(db *sqlx.DB, q *queue.Client, rdb *redis.Client, repo transaction.Repository) *Worker {
	return &Worker{db: db, queue: q, redis: rdb, repo: repo}
}

// Start spawns `concurrency` goroutines consuming from "transactions" queue.
// It blocks until ctx is cancelled.
func (w *Worker) Start(ctx context.Context, concurrency int) {
	msgs, err := w.queue.Consume("transactions")
	if err != nil {
		logger.L.Error("worker: failed to start consumer", "error", err)
		return
	}

	done := make(chan struct{})
	for i := range concurrency {
		go func(id int) {
			defer func() { done <- struct{}{} }()
			for {
				select {
				case <-ctx.Done():
					return
				case msg, ok := <-msgs:
					if !ok {
						return
					}
					w.process(ctx, &msg)
				}
			}
		}(i)
	}

	for range concurrency {
		<-done
	}
}

func (w *Worker) process(ctx context.Context, msg *amqp.Delivery) {
	var payload service.TxMessage
	if err := json.Unmarshal(msg.Body, &payload); err != nil {
		logger.L.Error("worker: bad message payload", "error", err)
		_ = msg.Nack(false, false) // send to DLQ
		return
	}

	// Idempotency: skip if already settled.
	existing, err := w.repo.GetByID(ctx, payload.TXID)
	if err == nil && existing.Status == transaction.StatusCompleted {
		logger.L.Info("worker: transaction already completed, skipping", "tx_id", payload.TXID)
		_ = msg.Ack(false)
		return
	}

	if err := w.settle(ctx, payload); err != nil {
		logger.L.Error("worker: failed to settle transaction", "tx_id", payload.TXID, "error", err)
		_ = w.repo.UpdateStatus(ctx, payload.TXID, transaction.StatusFailed)
		_ = msg.Nack(false, false) // send to DLQ
		return
	}

	w.invalidateBalanceCache(ctx, payload.SourceAccount, payload.DestAccount)
	w.invalidateTxStatusCache(ctx, payload.TXID)
	_ = msg.Ack(false)
}

// settle atomically debits source, credits destination, and marks the transaction completed.
func (w *Worker) settle(ctx context.Context, payload service.TxMessage) error {
	dbTx, err := w.db.BeginTxx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return fmt.Errorf("begin transaction: %w", err)
	}
	defer func() { _ = dbTx.Rollback() }()

	// Lock source account and read balance.
	var balance float64
	err = dbTx.QueryRowContext(ctx,
		`SELECT balance FROM accounts WHERE id = $1 FOR UPDATE`,
		payload.SourceAccount).Scan(&balance)
	if errors.Is(err, sql.ErrNoRows) {
		return fmt.Errorf("source account %d not found", payload.SourceAccount)
	}
	if err != nil {
		return fmt.Errorf("query source account: %w", err)
	}

	if balance < payload.Amount {
		return fmt.Errorf("insufficient funds: balance %.2f < amount %.2f", balance, payload.Amount)
	}

	// Debit source.
	if _, err = dbTx.ExecContext(ctx,
		`UPDATE accounts SET balance = balance - $1, updated_at = NOW() WHERE id = $2`,
		payload.Amount, payload.SourceAccount); err != nil {
		return fmt.Errorf("debit source: %w", err)
	}

	// Credit destination.
	if _, err = dbTx.ExecContext(ctx,
		`UPDATE accounts SET balance = balance + $1, updated_at = NOW() WHERE id = $2`,
		payload.Amount, payload.DestAccount); err != nil {
		return fmt.Errorf("credit dest: %w", err)
	}

	// Mark transaction completed.
	if _, err = dbTx.ExecContext(ctx,
		`UPDATE transactions SET status = 'completed', updated_at = NOW() WHERE id = $1`,
		payload.TXID); err != nil {
		return fmt.Errorf("update transaction status: %w", err)
	}

	return dbTx.Commit()
}

func (w *Worker) invalidateBalanceCache(ctx context.Context, accountIDs ...int64) {
	if w.redis == nil {
		return
	}
	keys := make([]string, len(accountIDs))
	for i, id := range accountIDs {
		keys[i] = fmt.Sprintf("balance:%d", id)
	}
	w.redis.Del(ctx, keys...)
}

func (w *Worker) invalidateTxStatusCache(ctx context.Context, txID string) {
	if w.redis == nil {
		return
	}
	w.redis.Del(ctx, fmt.Sprintf("tx_status:%s", txID))
}
