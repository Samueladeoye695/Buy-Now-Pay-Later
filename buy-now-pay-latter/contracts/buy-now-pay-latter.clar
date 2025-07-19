;; BNPL Chain - Buy Now Pay Later Smart Contract
;; A comprehensive BNPL platform on Stacks blockchain

;; =============================================================================
;; CONSTANTS
;; =============================================================================

(define-constant contract-owner tx-sender)
(define-constant platform-name "BNPL Chain")

;; Credit limits and rates
(define-constant min-purchase u100000) ;; 0.1 STX minimum
(define-constant max-credit-limit u100000000000) ;; 100,000 STX
(define-constant base-interest-rate u1500) ;; 15% APR for poor credit
(define-constant excellent-credit-rate u0) ;; 0% for excellent credit
(define-constant late-fee-rate u250) ;; 2.5%
(define-constant max-late-fee u25000000) ;; 25 STX max

;; Payment plan types
(define-constant plan-4-payments u4)
(define-constant plan-6-payments u6)
(define-constant plan-12-payments u12)

;; Credit score ranges
(define-constant excellent-credit u750)
(define-constant good-credit u700)
(define-constant fair-credit u650)
(define-constant poor-credit u550)

;; Account types
(define-constant consumer-account u1)
(define-constant merchant-account u2)
(define-constant business-account u3)

;; Merchant fees (basis points)
(define-constant merchant-fee-rate u500) ;; 5%
(define-constant transaction-fee u300) ;; 3%

;; =============================================================================
;; ERROR CONSTANTS
;; =============================================================================

(define-constant err-unauthorized (err u100))
(define-constant err-account-exists (err u101))
(define-constant err-account-not-found (err u102))
(define-constant err-insufficient-balance (err u103))
(define-constant err-invalid-amount (err u104))
(define-constant err-account-suspended (err u105))
(define-constant err-credit-declined (err u106))
(define-constant err-insufficient-credit (err u107))
(define-constant err-payment-overdue (err u108))
(define-constant err-invalid-payment-plan (err u109))
(define-constant err-merchant-not-verified (err u110))
(define-constant err-purchase-limit-exceeded (err u111))
(define-constant err-payment-failed (err u112))
(define-constant err-purchase-not-found (err u113))
(define-constant err-payment-not-due (err u114))
(define-constant err-already-paid (err u115))

;; =============================================================================
;; DATA VARIABLES
;; =============================================================================

(define-data-var next-account-id uint u1)
(define-data-var next-purchase-id uint u1)
(define-data-var next-payment-id uint u1)
(define-data-var platform-revenue uint u0)
(define-data-var total-purchases uint u0)
(define-data-var total-outstanding uint u0)

;; =============================================================================
;; DATA MAPS
;; =============================================================================

;; Account structure for BNPL users
(define-map accounts
    principal
    {
        account-id: uint,
        account-type: uint,
        balance: uint,
        credit-limit: uint,
        credit-used: uint,
        credit-score: uint,
        created-at: uint,
        last-activity: uint,
        is-active: bool,
        is-suspended: bool,
        kyc-verified: bool,
        payment-history-score: uint,
        total-purchases: uint,
        successful-payments: uint,
        missed-payments: uint,
        full-name: (string-ascii 100),
        email: (string-ascii 100),
        phone: (string-ascii 20)
    }
)

;; Purchase/Loan structure
(define-map purchases
    uint
    {
        purchase-id: uint,
        consumer: principal,
        merchant: (optional principal),
        purchase-amount: uint,
        remaining-balance: uint,
        payment-plan: uint,
        payment-amount: uint,
        payments-made: uint,
        total-payments: uint,
        interest-rate: uint,
        created-at: uint,
        next-payment-due: uint,
        status: (string-ascii 20),
        description: (string-ascii 200),
        is-autopay: bool,
        late-fees: uint
    }
)

;; Individual payment records
(define-map payments
    uint
    {
        payment-id: uint,
        purchase-id: uint,
        payer: principal,
        amount: uint,
        payment-date: uint,
        payment-type: (string-ascii 20),
        is-late: bool,
        late-fee: uint
    }
)

;; User's purchase history
(define-map user-purchases
    principal
    (list 50 uint)
)

;; Merchant information
(define-map merchants
    principal
    {
        business-name: (string-ascii 100),
        verification-status: (string-ascii 20),
        monthly-volume: uint,
        total-sales: uint,
        fee-rate: uint,
        settlement-account: (string-ascii 100),
        is-active: bool
    }
)

;; Credit score history
(define-map credit-history
    principal
    {
        previous-score: uint,
        current-score: uint,
        last-updated: uint,
        score-changes: (list 10 uint)
    }
)

;; Autopay settings
(define-map autopay-settings
    principal
    {
        is-enabled: bool,
        funding-source: (string-ascii 50),
        backup-source: (string-ascii 50),
        notification-enabled: bool
    }
)

;; =============================================================================
;; HELPER FUNCTIONS
;; =============================================================================

;; Helper function to get minimum of two values
(define-private (min-uint (a uint) (b uint))
    (if (<= a b) a b)
)

;; Helper function to get maximum of two values  
(define-private (max-uint (a uint) (b uint))
    (if (>= a b) a b)
)

;; Calculate interest rate based on credit score
(define-private (get-interest-rate (credit-score uint))
    (if (>= credit-score excellent-credit)
        u0
        (if (>= credit-score good-credit)
            u500  ;; 5%
            (if (>= credit-score fair-credit)
                u1000 ;; 10%
                base-interest-rate ;; 15%
            )
        )
    )
)

;; Calculate payment amount based on plan
(define-private (calculate-payment-amount (amount uint) (plan uint) (interest-rate uint))
    (let
        (
            (total-with-interest (+ amount (/ (* amount interest-rate) u10000)))
        )
        (/ total-with-interest plan)
    )
)

;; Calculate credit limit based on score and history
(define-private (calculate-credit-limit (credit-score uint) (payment-history uint))
    (let
        (
            (base-limit (if (>= credit-score excellent-credit)
                u50000000000  ;; 50,000 STX
                (if (>= credit-score good-credit)
                    u25000000000  ;; 25,000 STX
                    (if (>= credit-score fair-credit)
                        u10000000000  ;; 10,000 STX
                        u5000000000   ;; 5,000 STX
                    )
                )
            ))
            (history-multiplier (+ u100 (/ payment-history u10))) ;; Bonus for good history
        )
        (/ (* base-limit history-multiplier) u100)
    )
)

;; Update credit score based on payment behavior
(define-private (update-credit-score (user principal) (payment-behavior (string-ascii 20)))
    (let
        (
            (account-data (unwrap-panic (get-account user)))
            (current-score (get credit-score account-data))
            (score-change (if (is-eq payment-behavior "on-time")
                u5
                (if (is-eq payment-behavior "early")
                    u10
                    (if (is-eq payment-behavior "late")
                        (- u0 u15)
                        u0
                    )
                )
            ))
            (new-score (+ current-score score-change))
        )
        (begin
            (map-set accounts user
                (merge account-data { credit-score: new-score })
            )
            (map-set credit-history user
                {
                    previous-score: current-score,
                    current-score: new-score,
                    last-updated: stacks-block-height,
                    score-changes: (list score-change)
                }
            )
            new-score
        )
    )
)

;; Record payment transaction
(define-private (record-payment 
    (purchase-id uint)
    (payer principal)
    (amount uint)
    (payment-type (string-ascii 20))
    (is-late bool))
    (let
        (
            (payment-id (var-get next-payment-id))
            (late-fee (if is-late 
                (min-uint (/ (* amount late-fee-rate) u10000) max-late-fee)
                u0))
        )
        (begin
            (map-set payments payment-id
                {
                    payment-id: payment-id,
                    purchase-id: purchase-id,
                    payer: payer,
                    amount: amount,
                    payment-date: stacks-block-height,
                    payment-type: payment-type,
                    is-late: is-late,
                    late-fee: late-fee
                }
            )
            (var-set next-payment-id (+ payment-id u1))
            payment-id
        )
    )
)

;; =============================================================================
;; READ-ONLY FUNCTIONS
;; =============================================================================

;; Get account details
(define-read-only (get-account (user principal))
    (map-get? accounts user)
)

;; Get available credit
(define-read-only (get-available-credit (user principal))
    (match (get-account user)
        account-data 
        (- (get credit-limit account-data) (get credit-used account-data))
        u0
    )
)

;; Get purchase details
(define-read-only (get-purchase (purchase-id uint))
    (map-get? purchases purchase-id)
)

;; Get user's purchases
(define-read-only (get-user-purchases (user principal))
    (default-to (list) (map-get? user-purchases user))
)

;; Get payment details
(define-read-only (get-payment (payment-id uint))
    (map-get? payments payment-id)
)

;; Get merchant info
(define-read-only (get-merchant (merchant principal))
    (map-get? merchants merchant)
)

;; Get credit score
(define-read-only (get-credit-score (user principal))
    (match (get-account user)
        account-data (get credit-score account-data)
        u0
    )
)

;; Get next payment due
(define-read-only (get-next-payment-due (user principal))
    (let
        (
            (user-purchase-ids (get-user-purchases user))
            (active-purchases (filter is-purchase-active user-purchase-ids))
        )
        (if (> (len active-purchases) u0)
            (some (get-earliest-due-date active-purchases))
            none
        )
    )
)

;; Helper to check if purchase is active
(define-private (is-purchase-active (purchase-id uint))
    (match (get-purchase purchase-id)
        purchase-data (not (is-eq (get status purchase-data) "paid"))
        false
    )
)

;; Helper to get earliest due date
(define-private (get-earliest-due-date (purchase-ids (list 50 uint)))
    (fold get-min-due-date purchase-ids none)
)

(define-private (get-min-due-date (purchase-id uint) (current-min (optional uint)))
    (match (get-purchase purchase-id)
        purchase-data
        (let ((due-date (get next-payment-due purchase-data)))
            (match current-min
                min-date (some (min-uint due-date min-date))
                (some due-date)
            )
        )
        current-min
    )
)

;; Get platform statistics
(define-read-only (get-platform-stats)
    {
        total-purchases: (var-get total-purchases),
        total-outstanding: (var-get total-outstanding),
        platform-revenue: (var-get platform-revenue),
        total-accounts: (- (var-get next-account-id) u1)
    }
)

;; Check if account exists
(define-read-only (account-exists (user principal))
    (is-some (get-account user))
)

;; =============================================================================
;; PUBLIC FUNCTIONS
;; =============================================================================

;; Create BNPL account
(define-public (create-account 
    (account-type uint)
    (full-name (string-ascii 100))
    (email (string-ascii 100))
    (phone (string-ascii 20)))
    (let
        (
            (account-id (var-get next-account-id))
            (initial-credit-score u650)
            (initial-credit-limit (calculate-credit-limit initial-credit-score u0))
        )
        (begin
            ;; Check if account already exists
            (asserts! (not (account-exists tx-sender)) err-account-exists)
            
            ;; Validate account type
            (asserts! (or (is-eq account-type consumer-account)
                         (or (is-eq account-type merchant-account)
                             (is-eq account-type business-account))) err-invalid-amount)
            
            ;; Create account
            (map-set accounts tx-sender
                {
                    account-id: account-id,
                    account-type: account-type,
                    balance: u0,
                    credit-limit: initial-credit-limit,
                    credit-used: u0,
                    credit-score: initial-credit-score,
                    created-at: stacks-block-height,
                    last-activity: stacks-block-height,
                    is-active: true,
                    is-suspended: false,
                    kyc-verified: false,
                    payment-history-score: u0,
                    total-purchases: u0,
                    successful-payments: u0,
                    missed-payments: u0,
                    full-name: full-name,
                    email: email,
                    phone: phone
                }
            )
            
            ;; Initialize user purchases list
            (map-set user-purchases tx-sender (list))
            
            ;; Initialize credit history
            (map-set credit-history tx-sender
                {
                    previous-score: u0,
                    current-score: initial-credit-score,
                    last-updated: stacks-block-height,
                    score-changes: (list)
                }
            )
            
            ;; Update counter
            (var-set next-account-id (+ account-id u1))
            
            (ok account-id)
        )
    )
)

;; Make a purchase with BNPL
(define-public (make-purchase 
    (amount uint)
    (payment-plan uint)
    (merchant (optional principal))
    (description (string-ascii 200)))
    (let
        (
            (account-data (unwrap! (get-account tx-sender) err-account-not-found))
            (purchase-id (var-get next-purchase-id))
            (credit-score (get credit-score account-data))
            (available-credit (get-available-credit tx-sender))
            (interest-rate (get-interest-rate credit-score))
            (payment-amount (calculate-payment-amount amount payment-plan interest-rate))
            (current-purchases (get-user-purchases tx-sender))
        )
        (begin
            ;; Validate purchase
            (asserts! (>= amount min-purchase) err-invalid-amount)
            (asserts! (get is-active account-data) err-account-suspended)
            (asserts! (not (get is-suspended account-data)) err-account-suspended)
            (asserts! (get kyc-verified account-data) err-credit-declined)
            
            ;; Check credit availability
            (asserts! (>= available-credit amount) err-insufficient-credit)
            
            ;; Validate payment plan
            (asserts! (or (is-eq payment-plan plan-4-payments)
                         (or (is-eq payment-plan plan-6-payments)
                             (is-eq payment-plan plan-12-payments))) err-invalid-payment-plan)
            
            ;; Create purchase record
            (map-set purchases purchase-id
                {
                    purchase-id: purchase-id,
                    consumer: tx-sender,
                    merchant: merchant,
                    purchase-amount: amount,
                    remaining-balance: amount,
                    payment-plan: payment-plan,
                    payment-amount: payment-amount,
                    payments-made: u0,
                    total-payments: payment-plan,
                    interest-rate: interest-rate,
                    created-at: stacks-block-height,
                    next-payment-due: (+ stacks-block-height u4320), ;; 30 days
                    status: "active",
                    description: description,
                    is-autopay: false,
                    late-fees: u0
                }
            )
            
            ;; Update user's credit usage
            (map-set accounts tx-sender
                (merge account-data
                    {
                        credit-used: (+ (get credit-used account-data) amount),
                        total-purchases: (+ (get total-purchases account-data) u1),
                        last-activity: stacks-block-height
                    }
                )
            )
            
            ;; Add to user's purchase list
            (map-set user-purchases tx-sender 
                (unwrap-panic (as-max-len? (append current-purchases purchase-id) u50)))
            
            ;; Pay merchant if specified
            (match merchant
                merchant-address
                (begin
                    (let
                        (
                            (merchant-fee (/ (* amount merchant-fee-rate) u10000))
                            (merchant-payment (- amount merchant-fee))
                        )
                        ;; Transfer to merchant (minus fee)
                        (try! (stx-transfer? merchant-payment tx-sender merchant-address))
                        ;; Add fee to platform revenue
                        (var-set platform-revenue (+ (var-get platform-revenue) merchant-fee))
                    )
                )
                ;; If no merchant, funds stay in platform
                (var-set platform-revenue (+ (var-get platform-revenue) amount))
            )
            
            ;; Update counters
            (var-set next-purchase-id (+ purchase-id u1))
            (var-set total-purchases (+ (var-get total-purchases) amount))
            (var-set total-outstanding (+ (var-get total-outstanding) amount))
            
            (ok purchase-id)
        )
    )
)

;; Make payment on purchase
(define-public (make-payment (purchase-id uint) (amount uint))
    (let
        (
            (purchase-data (unwrap! (get-purchase purchase-id) err-purchase-not-found))
            (account-data (unwrap! (get-account tx-sender) err-account-not-found))
            (remaining-balance (get remaining-balance purchase-data))
            (payment-amount (get payment-amount purchase-data))
            (is-late (> stacks-block-height (get next-payment-due purchase-data)))
            (late-fee (if is-late 
                (min-uint (/ (* amount late-fee-rate) u10000) max-late-fee)
                u0))
            (total-payment (+ amount late-fee))
            (new-remaining-balance (- remaining-balance amount))
            (new-payments-made (+ (get payments-made purchase-data) u1))
            (next-due-date (+ stacks-block-height u4320)) ;; Next 30 days
        )
        (begin
            ;; Validate payment
            (asserts! (is-eq (get consumer purchase-data) tx-sender) err-unauthorized)
            (asserts! (> remaining-balance u0) err-already-paid)
            (asserts! (>= amount payment-amount) err-invalid-amount)
            
            ;; Check sufficient balance for payment + late fee
            (asserts! (>= (get balance account-data) total-payment) err-insufficient-balance)
            
            ;; Record payment
            (record-payment purchase-id tx-sender amount "regular" is-late)
            
            ;; Update purchase
            (map-set purchases purchase-id
                (merge purchase-data
                    {
                        remaining-balance: new-remaining-balance,
                        payments-made: new-payments-made,
                        next-payment-due: (if (is-eq new-remaining-balance u0) u0 next-due-date),
                        status: (if (is-eq new-remaining-balance u0) "paid" "active"),
                        late-fees: (+ (get late-fees purchase-data) late-fee)
                    }
                )
            )
            
            ;; Update user account
            (map-set accounts tx-sender
                (merge account-data
                    {
                        balance: (- (get balance account-data) total-payment),
                        credit-used: (- (get credit-used account-data) amount),
                        successful-payments: (+ (get successful-payments account-data) u1),
                        last-activity: stacks-block-height
                    }
                )
            )
            
            ;; Update credit score
            (update-credit-score tx-sender (if is-late "late" "on-time"))
            
            ;; Update platform stats
            (var-set total-outstanding (- (var-get total-outstanding) amount))
            (var-set platform-revenue (+ (var-get platform-revenue) late-fee))
            
            (ok new-remaining-balance)
        )
    )
)

;; Pay off purchase early
(define-public (pay-early (purchase-id uint))
    (let
        (
            (purchase-data (unwrap! (get-purchase purchase-id) err-purchase-not-found))
            (remaining-balance (get remaining-balance purchase-data))
        )
        (begin
            ;; Validate
            (asserts! (is-eq (get consumer purchase-data) tx-sender) err-unauthorized)
            (asserts! (> remaining-balance u0) err-already-paid)
            
            ;; Make full payment
            (try! (make-payment purchase-id remaining-balance))
            
            ;; Bonus credit score for early payment
            (update-credit-score tx-sender "early")
            
            (ok true)
        )
    )
)

;; Register as merchant
(define-public (register-merchant 
    (business-name (string-ascii 100))
    (monthly-volume uint)
    (settlement-account (string-ascii 100)))
    (let
        (
            (account-data (unwrap! (get-account tx-sender) err-account-not-found))
        )
        (begin
            ;; Validate merchant account type
            (asserts! (is-eq (get account-type account-data) merchant-account) err-unauthorized)
            
            ;; Register merchant
            (map-set merchants tx-sender
                {
                    business-name: business-name,
                    verification-status: "pending",
                    monthly-volume: monthly-volume,
                    total-sales: u0,
                    fee-rate: merchant-fee-rate,
                    settlement-account: settlement-account,
                    is-active: false
                }
            )
            
            (ok true)
        )
    )
)

;; Setup autopay
(define-public (setup-autopay 
    (funding-source (string-ascii 50))
    (backup-source (string-ascii 50)))
    (begin
        (asserts! (account-exists tx-sender) err-account-not-found)
        
        (map-set autopay-settings tx-sender
            {
                is-enabled: true,
                funding-source: funding-source,
                backup-source: backup-source,
                notification-enabled: true
            }
        )
        
        (ok true)
    )
)

;; Deposit funds to account
(define-public (deposit (amount uint))
    (let
        (
            (account-data (unwrap! (get-account tx-sender) err-account-not-found))
            (new-balance (+ (get balance account-data) amount))
        )
        (begin
            (asserts! (> amount u0) err-invalid-amount)
            
            ;; Update balance
            (map-set accounts tx-sender
                (merge account-data 
                    { 
                        balance: new-balance,
                        last-activity: stacks-block-height
                    }
                )
            )
            
            (ok new-balance)
        )
    )
)

;; =============================================================================
;; ADMIN FUNCTIONS
;; =============================================================================

;; Verify KYC (admin only)
(define-public (verify-kyc (user principal))
    (let
        (
            (account-data (unwrap! (get-account user) err-account-not-found))
        )
        (begin
            (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
            
            (map-set accounts user
                (merge account-data { kyc-verified: true })
            )
            
            (ok true)
        )
    )
)

;; Verify merchant (admin only)
(define-public (verify-merchant (merchant principal))
    (let
        (
            (merchant-data (unwrap! (get-merchant merchant) err-merchant-not-verified))
        )
        (begin
            (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
            
            (map-set merchants merchant
                (merge merchant-data 
                    { 
                        verification-status: "verified",
                        is-active: true
                    }
                )
            )
            
            (ok true)
        )
    )
)

;; Suspend account (admin only)
(define-public (suspend-account (user principal))
    (let
        (
            (account-data (unwrap! (get-account user) err-account-not-found))
        )
        (begin
            (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
            
            (map-set accounts user
                (merge account-data { is-suspended: true })
            )
            
            (ok true)
        )
    )
)