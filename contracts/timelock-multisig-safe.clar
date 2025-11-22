;; =======================================================
;; timelock-multisig-safe
;; A multi-signature wallet with timelock security
;; =======================================================

;; --------------------------------------------
;; Constants
;; --------------------------------------------
(define-constant ERR-NOT-OWNER u1)
(define-constant ERR-TX-NOT-FOUND u2)
(define-constant ERR-ALREADY-EXECUTED u3)
(define-constant ERR-CANCELLED u4)
(define-constant ERR-NOT-ENOUGH-APPROVALS u5)
(define-constant ERR-TIMELOCK-NOT-SATISFIED u6)

;; --------------------------------------------
;; Variables
;; --------------------------------------------
;; Fixed data structure - using define-data-var instead of define-private function
(define-data-var tx-counter uint u0)
(define-data-var contract-owner principal tx-sender)
(define-data-var threshold uint u2)
(define-data-var timelock-duration uint u100)

;; --------------------------------------------
;; Maps
;; --------------------------------------------
;; Fixed data structure - using define-map instead of define-private function
(define-map transactions uint 
  {
    to: principal,
    amount: uint,
    memo: (optional (buff 32)),
    approvals: uint,
    created-at: uint,
    scheduled-at: (optional uint),
    executed: bool,
    cancelled: bool
  }
)

;; --------------------------------------------
;; Submit a new transaction
;; --------------------------------------------
(define-public (submit (to principal) (amount uint) (memo (optional (buff 32))))
  (begin
    (asserts! (is-owner) (err ERR-NOT-OWNER))

    (var-set tx-counter (+ (var-get tx-counter) u1))
    (let ((id (var-get tx-counter)))
      (map-set transactions id
        {
          to: to,
          amount: amount,
          memo: memo,
          approvals: u0,
          created-at: burn-block-height,
          scheduled-at: none,
          executed: false,
          cancelled: false
        })
      (ok id)
    )
  )
)

;; --------------------------------------------
;; Execute after timelock delay
;; --------------------------------------------
(define-public (execute (id uint))
  (let ((tx (unwrap! (map-get? transactions id) (err ERR-TX-NOT-FOUND))))
    (begin
      (asserts! (not (get executed tx)) (err ERR-ALREADY-EXECUTED))
      (asserts! (not (get cancelled tx)) (err ERR-CANCELLED))

      ;; must meet quorum
      (asserts! (>= (get approvals tx) (var-get threshold)) (err ERR-NOT-ENOUGH-APPROVALS))

      ;; must satisfy timelock
      (let ((start (unwrap! (get scheduled-at tx) (err ERR-TIMELOCK-NOT-SATISFIED))))
        (asserts! (>= burn-block-height (+ start (var-get timelock-duration))) (err ERR-TIMELOCK-NOT-SATISFIED))
      )

      ;; transfer STX from contract to recipient
      (try! (as-contract (stx-transfer? (get amount tx) tx-sender (get to tx))))

      ;; mark as executed
      (map-set transactions id (merge tx { executed: true }))
      (ok true)
    )
  )
)

;; --------------------------------------------
;; Approve a transaction
;; --------------------------------------------
(define-public (approve (id uint))
  (begin
    (asserts! (is-owner) (err ERR-NOT-OWNER))

    (let ((tx (unwrap! (map-get? transactions id) (err ERR-TX-NOT-FOUND))))
      (begin
        (asserts! (not (get executed tx)) (err ERR-ALREADY-EXECUTED))
        (asserts! (not (get cancelled tx)) (err ERR-CANCELLED))

        ;; increment approvals
        (let ((new-approvals (+ (get approvals tx) u1)))
          (map-set transactions id (merge tx { approvals: new-approvals }))
          (ok true)
        )
      )
    )
  )
)

;; --------------------------------------------
;; Cancel a transaction
;; --------------------------------------------
(define-public (cancel (id uint))
  (let ((tx (unwrap! (map-get? transactions id) (err ERR-TX-NOT-FOUND))))
    (begin
      (asserts! (is-owner) (err ERR-NOT-OWNER))
      (asserts! (not (get executed tx)) (err ERR-ALREADY-EXECUTED))

      ;; mark as cancelled
      (map-set transactions id (merge tx { cancelled: true }))
      (ok true)
    )
  )
)

;; --------------------------------------------
;; Schedule a transaction
;; --------------------------------------------
;; Renamed parameter from block-height to target-height to avoid reserved word conflict
(define-public (schedule (id uint) (target-height uint))
  (begin
    (asserts! (is-owner) (err ERR-NOT-OWNER))

    (let ((tx (unwrap! (map-get? transactions id) (err ERR-TX-NOT-FOUND))))
      (begin
        (asserts! (not (get executed tx)) (err ERR-ALREADY-EXECUTED))
        (asserts! (not (get cancelled tx)) (err ERR-CANCELLED))

        ;; set scheduled block height
        (map-set transactions id (merge tx { scheduled-at: (some target-height) }))
        (ok true)
      )
    )
  )
)

;; --------------------------------------------
;; Check transaction status
;; --------------------------------------------
(define-read-only (check-status (id uint))
  (let ((tx (unwrap! (map-get? transactions id) (err ERR-TX-NOT-FOUND))))
    (ok tx)
  )
)

;; --------------------------------------------
;; Helper function to check if the caller is an owner
;; --------------------------------------------
(define-private (is-owner)
  (is-eq tx-sender (var-get contract-owner))
)
