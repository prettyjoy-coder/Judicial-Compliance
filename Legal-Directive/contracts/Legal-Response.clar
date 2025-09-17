;; Judicial Compliance Tracking System Smart Contract
;; 
;; A blockchain-based legal directive management platform that enables judicial authorities
;; to issue compliance orders, track response timelines, manage multi-party proceedings,
;; and maintain immutable audit trails. The system ensures transparent accountability
;; in legal processes through automated deadline monitoring, secure evidence submission,
;; and comprehensive reporting capabilities for regulatory oversight.

;; Error constant definitions
(define-constant ERR-UNAUTHORIZED-ACCESS (err u100))
(define-constant ERR-LEGAL-DIRECTIVE-NOT-FOUND (err u101))
(define-constant ERR-INSUFFICIENT-AUTHORITY (err u102))
(define-constant ERR-DUPLICATE-RECORD-EXISTS (err u103))
(define-constant ERR-INVALID-STATUS-CHANGE (err u104))
(define-constant ERR-RESPONSE-DEADLINE-PASSED (err u105))
(define-constant ERR-INVALID-INPUT-PARAMETERS (err u106))
(define-constant ERR-RESPONSE-ALREADY-EXISTS (err u107))
(define-constant ERR-PARTICIPANT-CAPACITY-EXCEEDED (err u108))
(define-constant ERR-EMPTY-DESCRIPTION-NOT-ALLOWED (err u109))
(define-constant ERR-INVALID-DEADLINE-TIME (err u110))
(define-constant ERR-INVALID-PRINCIPAL-PROVIDED (err u111))
(define-constant ERR-INVALID-CASE-CATEGORY (err u112))
(define-constant ERR-RESPONSE-LENGTH-EXCEEDED (err u113))
(define-constant ERR-INVALID-COMPLIANCE-STATE (err u114))

;; System configuration constant
(define-constant contract-administrator tx-sender)
(define-constant maximum-proceeding-participants u100)
(define-constant batch-operation-limit u10)
(define-constant query-results-limit u50)
(define-constant response-content-max-length u1000)
(define-constant directive-description-max-length u500)
(define-constant reviewer-notes-max-length u200)

;; Compliance state definitions
(define-constant status-awaiting-response "pending")
(define-constant status-acknowledged-received "acknowledged")
(define-constant status-response-submitted "responded")
(define-constant status-review-in-progress "under-review")
(define-constant status-case-resolved "resolved")
(define-constant status-directive-cancelled "cancelled")
(define-constant status-deadline-expired "expired")

;; Legal case category definitions
(define-constant case-type-civil-matter "civil")
(define-constant case-type-criminal-matter "criminal")
(define-constant case-type-administrative-matter "administrative")
(define-constant case-type-regulatory-matter "regulatory")
(define-constant case-type-emergency-matter "emergency")

;; Priority level definitions
(define-constant priority-routine u1)
(define-constant priority-normal u5)
(define-constant priority-elevated u8)
(define-constant priority-critical u10)

;; System state tracking variables
(define-data-var next-directive-identifier uint u0)
(define-data-var total-submitted-responses uint u0)
(define-data-var system-active-status bool false)
(define-data-var current-active-directives uint u0)
(define-data-var total-expired-directives uint u0)

;; Primary data storage structures
(define-map judicial-directives-database
    uint  ;; directive-identifier
    {
        issuing-authority-principal: principal,
        target-respondent-principal: principal,
        directive-content-description: (string-utf8 500),
        compliance-deadline-block: uint,
        current-status-state: (string-ascii 20),
        creation-timestamp-block: uint,
        case-category-classification: (string-ascii 50),
        priority-urgency-level: uint,
        last-update-timestamp-block: uint,
        evidence-attachment-required: bool
    }
)

(define-map compliance-responses-database
    { directive-identifier: uint, respondent-principal: principal }
    {
        submitted-response-content: (string-utf8 1000),
        submission-timestamp-block: uint,
        processing-status-current: (string-ascii 20),
        evidence-cryptographic-hash: (optional (buff 32)),
        judicial-review-commentary: (optional (string-utf8 200)),
        response-completion-flag: bool
    }
)

(define-map authorized-judicial-principals principal bool)

(define-map eligible-respondent-principals principal bool)

(define-map proceeding-participants-roster
    uint  ;; directive-identifier
    (list 100 principal)
)

(define-map directive-configuration-parameters
    uint  ;; directive-identifier
    {
        evidence-submission-mandatory: bool,
        deadline-extension-permitted: bool,
        response-character-limit-maximum: uint,
        notification-delivery-confirmed: bool,
        automatic-expiration-active: bool
    }
)

(define-map status-classification-index
    { status-category: (string-ascii 20), directive-identifier: uint }
    bool
)

(define-map status-analytics-counters
    (string-ascii 20)
    uint
)

(define-map judicial-authority-metrics
    principal
    {
        total-directives-issued: uint,
        last-recorded-activity-block: uint,
        total-resolved-cases: uint
    }
)

;; Input validation helper functions
(define-private (validate-principal-not-null (principal-to-check principal))
    (not (is-eq principal-to-check 'SP000000000000000000002Q6VF78))
)

(define-private (validate-case-category-enum (category-value (string-ascii 50)))
    (or (is-eq category-value case-type-civil-matter)
        (is-eq category-value case-type-criminal-matter)
        (is-eq category-value case-type-administrative-matter)
        (is-eq category-value case-type-regulatory-matter)
        (is-eq category-value case-type-emergency-matter))
)

(define-private (validate-status-enum (status-value (string-ascii 20)))
    (or (is-eq status-value status-awaiting-response)
        (is-eq status-value status-acknowledged-received)
        (is-eq status-value status-response-submitted)
        (is-eq status-value status-review-in-progress)
        (is-eq status-value status-case-resolved)
        (is-eq status-value status-directive-cancelled)
        (is-eq status-value status-deadline-expired))
)

(define-private (validate-priority-range (priority-value uint))
    (and (>= priority-value priority-routine) 
         (<= priority-value priority-critical))
)

(define-private (validate-future-block-height (target-block uint))
    (> target-block block-height)
)

(define-private (validate-non-empty-description (description-content (string-utf8 500)))
    (> (len description-content) u0)
)

;; Authorization verification functions
(define-private (check-judicial-authorization (authority-principal principal))
    (default-to false (map-get? authorized-judicial-principals authority-principal))
)

(define-private (check-respondent-registration (respondent-principal principal))
    (default-to false (map-get? eligible-respondent-principals respondent-principal))
)

(define-private (verify-proceeding-membership (directive-identifier uint) (participant-principal principal))
    (match (map-get? proceeding-participants-roster directive-identifier)
        participants-list (is-some (index-of participants-list participant-principal))
        false
    )
)

(define-private (validate-status-transition-rules (current-state (string-ascii 20)) (target-state (string-ascii 20)))
    (or
        (and (is-eq current-state status-awaiting-response) 
             (or (is-eq target-state status-acknowledged-received)
                 (is-eq target-state status-response-submitted)
                 (is-eq target-state status-directive-cancelled)
                 (is-eq target-state status-deadline-expired)))
        (and (is-eq current-state status-acknowledged-received) 
             (or (is-eq target-state status-response-submitted)
                 (is-eq target-state status-review-in-progress)
                 (is-eq target-state status-deadline-expired)))
        (and (is-eq current-state status-response-submitted) 
             (or (is-eq target-state status-review-in-progress)
                 (is-eq target-state status-case-resolved)))
        (and (is-eq current-state status-review-in-progress) 
             (or (is-eq target-state status-case-resolved)
                 (is-eq target-state status-awaiting-response)))
        (and (is-eq current-state status-directive-cancelled) 
             (is-eq target-state status-awaiting-response))
    )
)

;; Status indexing management functions
(define-private (add-status-to-index (directive-identifier uint) (status-value (string-ascii 20)))
    (begin
        (map-set status-classification-index 
            { status-category: status-value, directive-identifier: directive-identifier } true)
        (map-set status-analytics-counters status-value 
            (+ (default-to u0 (map-get? status-analytics-counters status-value)) u1))
    )
)

(define-private (remove-status-from-index (directive-identifier uint) (status-value (string-ascii 20)))
    (begin
        (map-delete status-classification-index 
            { status-category: status-value, directive-identifier: directive-identifier })
        (let ((current-count (default-to u0 (map-get? status-analytics-counters status-value))))
            (if (> current-count u0)
                (map-set status-analytics-counters status-value (- current-count u1))
                true
            )
        )
    )
)

(define-private (update-status-index-mapping (directive-identifier uint) (old-status (string-ascii 20)) (new-status (string-ascii 20)))
    (begin
        (remove-status-from-index directive-identifier old-status)
        (add-status-to-index directive-identifier new-status)
    )
)

;; Activity tracking utility functions
(define-private (update-authority-activity-metrics (authority-principal principal) (increment-issued bool) (increment-resolved bool))
    (let ((current-metrics (default-to 
                             { total-directives-issued: u0, last-recorded-activity-block: u0, total-resolved-cases: u0 }
                             (map-get? judicial-authority-metrics authority-principal))))
        (map-set judicial-authority-metrics authority-principal
            {
                total-directives-issued: (if increment-issued 
                                 (+ (get total-directives-issued current-metrics) u1)
                                 (get total-directives-issued current-metrics)),
                last-recorded-activity-block: block-height,
                total-resolved-cases: (if increment-resolved
                                  (+ (get total-resolved-cases current-metrics) u1)
                                  (get total-resolved-cases current-metrics))
            }
        )
    )
)

;; System initialization and administration functions
(define-public (initialize-judicial-system)
    (begin
        (asserts! (is-eq tx-sender contract-administrator) ERR-UNAUTHORIZED-ACCESS)
        (asserts! (not (var-get system-active-status)) ERR-DUPLICATE-RECORD-EXISTS)
        (var-set system-active-status true)
        (map-set authorized-judicial-principals contract-administrator true)
        (update-authority-activity-metrics contract-administrator false false)
        (ok "Judicial compliance system successfully initialized")
    )
)

(define-public (authorize-judicial-principal (new-authority principal))
    (begin
        (asserts! (is-eq tx-sender contract-administrator) ERR-UNAUTHORIZED-ACCESS)
        (asserts! (validate-principal-not-null new-authority) ERR-INVALID-PRINCIPAL-PROVIDED)
        (asserts! (not (check-judicial-authorization new-authority)) ERR-DUPLICATE-RECORD-EXISTS)
        (map-set authorized-judicial-principals new-authority true)
        (update-authority-activity-metrics new-authority false false)
        (ok "Judicial authorization successfully granted")
    )
)

(define-public (revoke-judicial-authorization (authority-principal principal))
    (begin
        (asserts! (is-eq tx-sender contract-administrator) ERR-UNAUTHORIZED-ACCESS)
        (asserts! (check-judicial-authorization authority-principal) ERR-LEGAL-DIRECTIVE-NOT-FOUND)
        (map-delete authorized-judicial-principals authority-principal)
        (ok "Judicial authorization successfully revoked")
    )
)

(define-public (register-compliance-respondent (respondent-principal principal))
    (begin
        (asserts! (check-judicial-authorization tx-sender) ERR-INSUFFICIENT-AUTHORITY)
        (asserts! (validate-principal-not-null respondent-principal) ERR-INVALID-PRINCIPAL-PROVIDED)
        (map-set eligible-respondent-principals respondent-principal true)
        (ok "Compliance respondent successfully registered")
    )
)

;; Core directive management functions
(define-public (issue-judicial-directive 
    (target-respondent principal)
    (directive-description (string-utf8 500))
    (compliance-deadline uint)
    (case-category (string-ascii 50))
    (priority-level uint)
    (requires-evidence bool)
    (allows-extensions bool)
)
    (let
        (
            (new-directive-id (+ (var-get next-directive-identifier) u1))
            (current-block block-height)
        )
        (asserts! (check-judicial-authorization tx-sender) ERR-INSUFFICIENT-AUTHORITY)
        (asserts! (validate-principal-not-null target-respondent) ERR-INVALID-PRINCIPAL-PROVIDED)
        (asserts! (validate-future-block-height compliance-deadline) ERR-INVALID-DEADLINE-TIME)
        (asserts! (validate-non-empty-description directive-description) ERR-EMPTY-DESCRIPTION-NOT-ALLOWED)
        (asserts! (validate-case-category-enum case-category) ERR-INVALID-CASE-CATEGORY)
        (asserts! (validate-priority-range priority-level) ERR-INVALID-INPUT-PARAMETERS)
        
        (map-set judicial-directives-database new-directive-id
            {
                issuing-authority-principal: tx-sender,
                target-respondent-principal: target-respondent,
                directive-content-description: directive-description,
                compliance-deadline-block: compliance-deadline,
                current-status-state: status-awaiting-response,
                creation-timestamp-block: current-block,
                case-category-classification: case-category,
                priority-urgency-level: priority-level,
                last-update-timestamp-block: current-block,
                evidence-attachment-required: requires-evidence
            }
        )
        
        (map-set directive-configuration-parameters new-directive-id
            {
                evidence-submission-mandatory: requires-evidence,
                deadline-extension-permitted: allows-extensions,
                response-character-limit-maximum: response-content-max-length,
                notification-delivery-confirmed: false,
                automatic-expiration-active: true
            }
        )
        
        (map-set proceeding-participants-roster new-directive-id 
            (list tx-sender target-respondent))
        
        (add-status-to-index new-directive-id status-awaiting-response)
        (update-authority-activity-metrics tx-sender true false)
        
        (var-set next-directive-identifier new-directive-id)
        (var-set current-active-directives (+ (var-get current-active-directives) u1))
        
        (ok new-directive-id)
    )
)

(define-public (submit-compliance-response 
    (directive-identifier uint)
    (response-content (string-utf8 1000))
    (evidence-hash (optional (buff 32)))
)
    (let
        (
            (directive-record (unwrap! (map-get? judicial-directives-database directive-identifier) ERR-LEGAL-DIRECTIVE-NOT-FOUND))
            (configuration-settings (unwrap! (map-get? directive-configuration-parameters directive-identifier) ERR-LEGAL-DIRECTIVE-NOT-FOUND))
            (current-block block-height)
        )
        (asserts! (is-eq (get target-respondent-principal directive-record) tx-sender) ERR-INSUFFICIENT-AUTHORITY)
        (asserts! (< current-block (get compliance-deadline-block directive-record)) ERR-RESPONSE-DEADLINE-PASSED)
        (asserts! (or (is-eq (get current-status-state directive-record) status-awaiting-response)
                     (is-eq (get current-status-state directive-record) status-acknowledged-received)) ERR-INVALID-STATUS-CHANGE)
        (asserts! (is-none (map-get? compliance-responses-database 
                          { directive-identifier: directive-identifier, respondent-principal: tx-sender })) ERR-RESPONSE-ALREADY-EXISTS)
        (asserts! (<= (len response-content) (get response-character-limit-maximum configuration-settings)) ERR-RESPONSE-LENGTH-EXCEEDED)
        
        (asserts! (or (not (get evidence-submission-mandatory configuration-settings))
                     (is-some evidence-hash)) ERR-INVALID-INPUT-PARAMETERS)
        
        (map-set compliance-responses-database 
            { directive-identifier: directive-identifier, respondent-principal: tx-sender }
            {
                submitted-response-content: response-content,
                submission-timestamp-block: current-block,
                processing-status-current: "submitted",
                evidence-cryptographic-hash: evidence-hash,
                judicial-review-commentary: none,
                response-completion-flag: true
            }
        )
        
        (update-status-index-mapping directive-identifier (get current-status-state directive-record) status-response-submitted)
        (map-set judicial-directives-database directive-identifier
            (merge directive-record { 
                current-status-state: status-response-submitted,
                last-update-timestamp-block: current-block 
            })
        )
        
        (var-set total-submitted-responses (+ (var-get total-submitted-responses) u1))
        
        (ok "Compliance response successfully submitted")
    )
)

(define-public (update-directive-status 
    (directive-identifier uint) 
    (new-status (string-ascii 20))
    (reviewer-notes (optional (string-utf8 200)))
)
    (let
        (
            (directive-record (unwrap! (map-get? judicial-directives-database directive-identifier) ERR-LEGAL-DIRECTIVE-NOT-FOUND))
            (current-block block-height)
        )
        (asserts! (is-eq (get issuing-authority-principal directive-record) tx-sender) ERR-INSUFFICIENT-AUTHORITY)
        
        (asserts! (validate-status-enum new-status) ERR-INVALID-COMPLIANCE-STATE)
        (asserts! (validate-status-transition-rules (get current-status-state directive-record) new-status) ERR-INVALID-STATUS-CHANGE)
        
        (update-status-index-mapping directive-identifier (get current-status-state directive-record) new-status)
        
        (map-set judicial-directives-database directive-identifier
            (merge directive-record { 
                current-status-state: new-status,
                last-update-timestamp-block: current-block 
            })
        )
        
        (match reviewer-notes
            notes-content
            (match (map-get? compliance-responses-database 
                           { directive-identifier: directive-identifier, respondent-principal: (get target-respondent-principal directive-record) })
                existing-response
                (map-set compliance-responses-database
                    { directive-identifier: directive-identifier, respondent-principal: (get target-respondent-principal directive-record) }
                    (merge existing-response { judicial-review-commentary: (some notes-content) })
                )
                true
            )
            true
        )
        
        (if (is-eq new-status status-case-resolved)
            (update-authority-activity-metrics tx-sender false true)
            true
        )
        
        (ok "Directive status successfully updated")
    )
)

(define-public (add-proceeding-participant 
    (directive-identifier uint) 
    (participant-principal principal)
)
    (let
        (
            (directive-record (unwrap! (map-get? judicial-directives-database directive-identifier) ERR-LEGAL-DIRECTIVE-NOT-FOUND))
            (current-participants (default-to (list) (map-get? proceeding-participants-roster directive-identifier)))
        )
        (asserts! (is-eq (get issuing-authority-principal directive-record) tx-sender) ERR-INSUFFICIENT-AUTHORITY)
        (asserts! (validate-principal-not-null participant-principal) ERR-INVALID-PRINCIPAL-PROVIDED)
        (asserts! (is-none (index-of current-participants participant-principal)) ERR-DUPLICATE-RECORD-EXISTS)
        
        (map-set proceeding-participants-roster directive-identifier 
            (unwrap! (as-max-len? (append current-participants participant-principal) u100) 
                    ERR-PARTICIPANT-CAPACITY-EXCEEDED)
        )
        
        (ok "Participant successfully added to proceeding")
    )
)

;; Data retrieval functions
(define-read-only (get-directive-details (directive-identifier uint))
    (match (map-get? judicial-directives-database directive-identifier)
        directive-data (ok {
            directive-information: directive-data,
            configuration-parameters: (map-get? directive-configuration-parameters directive-identifier),
            participants-list: (default-to (list) (map-get? proceeding-participants-roster directive-identifier)),
            deadline-expired: (> block-height (get compliance-deadline-block directive-data))
        })
        ERR-LEGAL-DIRECTIVE-NOT-FOUND
    )
)

(define-read-only (get-response-details (directive-identifier uint) (respondent-principal principal))
    (ok (map-get? compliance-responses-database { directive-identifier: directive-identifier, respondent-principal: respondent-principal }))
)

(define-read-only (check-deadline-status (directive-identifier uint))
    (match (map-get? judicial-directives-database directive-identifier)
        directive-data (ok (> block-height (get compliance-deadline-block directive-data)))
        ERR-LEGAL-DIRECTIVE-NOT-FOUND
    )
)

(define-read-only (get-system-analytics)
    (ok {
        total-directives-created: (var-get next-directive-identifier),
        total-responses-submitted: (var-get total-submitted-responses),
        system-operational: (var-get system-active-status),
        active-directives-count: (var-get current-active-directives),
        expired-directives-count: (var-get total-expired-directives),
        pending-directives: (default-to u0 (map-get? status-analytics-counters status-awaiting-response)),
        responded-directives: (default-to u0 (map-get? status-analytics-counters status-response-submitted)),
        resolved-directives: (default-to u0 (map-get? status-analytics-counters status-case-resolved))
    })
)

(define-read-only (verify-judicial-authorization (authority-principal principal))
    (ok (check-judicial-authorization authority-principal))
)

(define-read-only (get-proceeding-participants (directive-identifier uint))
    (ok (default-to (list) (map-get? proceeding-participants-roster directive-identifier)))
)

(define-read-only (get-authority-metrics (authority-principal principal))
    (ok (map-get? judicial-authority-metrics authority-principal))
)

;; Analytics and reporting functions
(define-read-only (get-directives-by-status 
    (target-status (string-ascii 20)) 
    (start-index uint) 
    (limit uint))
    (let
        (
            (validated-limit (if (> limit query-results-limit) query-results-limit limit))
        )
        (if (validate-status-enum target-status)
            (ok {
                status-category: target-status,
                total-matching: (default-to u0 (map-get? status-analytics-counters target-status)),
                query-start: start-index,
                result-limit: validated-limit
            })
            ERR-INVALID-COMPLIANCE-STATE
        )
    )
)

(define-read-only (verify-status-membership (directive-identifier uint) (status-category (string-ascii 20)))
    (ok (default-to false 
        (map-get? status-classification-index { status-category: status-category, directive-identifier: directive-identifier })))
)

(define-read-only (get-status-count (status-category (string-ascii 20)))
    (if (validate-status-enum status-category)
        (ok (default-to u0 (map-get? status-analytics-counters status-category)))
        ERR-INVALID-COMPLIANCE-STATE
    )
)

(define-read-only (calculate-time-remaining (directive-identifier uint))
    (match (map-get? judicial-directives-database directive-identifier)
        directive-data 
        (if (> (get compliance-deadline-block directive-data) block-height)
            (ok (- (get compliance-deadline-block directive-data) block-height))
            (ok u0)
        )
        ERR-LEGAL-DIRECTIVE-NOT-FOUND
    )
)

(define-read-only (generate-directive-summary (directive-identifier uint))
    (match (map-get? judicial-directives-database directive-identifier)
        directive-data (ok {
            directive-id: directive-identifier,
            current-state: (get current-status-state directive-data),
            issuing-authority: (get issuing-authority-principal directive-data),
            target-respondent: (get target-respondent-principal directive-data),
            case-classification: (get case-category-classification directive-data),
            priority-level: (get priority-urgency-level directive-data),
            deadline-block: (get compliance-deadline-block directive-data),
            is-expired: (> block-height (get compliance-deadline-block directive-data)),
            blocks-until-deadline: (if (> (get compliance-deadline-block directive-data) block-height)
                                (- (get compliance-deadline-block directive-data) block-height)
                                u0)
        })
        ERR-LEGAL-DIRECTIVE-NOT-FOUND
    )
)

;; Batch processing functions
(define-public (create-multiple-directives 
    (directives-batch (list 10 { 
        target-respondent: principal, 
        directive-description: (string-utf8 500), 
        compliance-deadline: uint, 
        case-category: (string-ascii 50),
        priority-level: uint,
        requires-evidence: bool,
        allows-extensions: bool
    }))
)
    (ok (map process-single-directive directives-batch))
)

(define-private (process-single-directive 
    (directive-data { 
        target-respondent: principal, 
        directive-description: (string-utf8 500), 
        compliance-deadline: uint, 
        case-category: (string-ascii 50),
        priority-level: uint,
        requires-evidence: bool,
        allows-extensions: bool
    })
)
    (issue-judicial-directive 
        (get target-respondent directive-data)
        (get directive-description directive-data)
        (get compliance-deadline directive-data)
        (get case-category directive-data)
        (get priority-level directive-data)
        (get requires-evidence directive-data)
        (get allows-extensions directive-data)
    )
)