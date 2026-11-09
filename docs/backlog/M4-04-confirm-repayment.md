Confirm repayment screen
area:flutter,type:feature,agent:claude
M4 Loans
**Owner:** Principal Flutter · **Depends on:** M4-01, M4-03 · **Canvas:** ConfirmRepayment (note n23)

## Acceptance criteria
- [ ] Receipt view of the claim with reference and outstanding-after-confirmation
- [ ] Primary button repeats the amount ('Confirm ₹25,000 received'); 'Didn't receive' equally available with a reason
- [ ] Confirmation is final and stated as such

## Test plan
Goldens 390/360; widget tests confirm and dispute; semantics read the amount in rupees.
