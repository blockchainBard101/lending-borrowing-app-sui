REWARD_SCALE = 1000  # To avoid decimals, all reward shares are scaled

class Lender:
    def __init__(self, name, deposit):
        self.name = name
        self.amount = deposit
        self.reward_debt = 0
        self.total_claimed = 0

    def claim_reward(self, accumulated_reward_per_share):
        total_earned = (self.amount * accumulated_reward_per_share) // REWARD_SCALE
        pending = total_earned - self.reward_debt
        self.total_claimed += pending
        self.reward_debt = total_earned
        return pending

class LendingPool:
    def __init__(self):
        self.total_liquidity = 0
        self.accumulated_reward_per_share = 0
        self.lenders = []

    def add_lender(self, lender):
        self.lenders.append(lender)
        self.total_liquidity += lender.amount
        lender.reward_debt = (lender.amount * self.accumulated_reward_per_share) // REWARD_SCALE

    def distribute_reward(self, reward):
        if self.total_liquidity == 0:
            return
        increment = (reward * REWARD_SCALE) // self.total_liquidity
        self.accumulated_reward_per_share += increment
        print(f"\n[REWARD DISTRIBUTED] +{reward} USDC → New ARPS: {self.accumulated_reward_per_share}")

    def claim_single(self, lender):
        reward = lender.claim_reward(self.accumulated_reward_per_share)
        print(f"{lender.name} claimed: {reward} USDC | Total claimed: {lender.total_claimed}")

    def claim_all(self):
        print("\n[CLAIM ALL]")
        for lender in self.lenders:
            self.claim_single(lender)

# ---- SCENARIO ----
pool = LendingPool()
alice = Lender("Alice", 1000)  # 25%
bob = Lender("Bob", 3000)      # 75%

# Step 1: Add both lenders
pool.add_lender(alice)
pool.add_lender(bob)

# Step 2: Borrower pays 100 USDC
pool.distribute_reward(100)

# Step 3: Alice claims; Bob does NOT
print("\n[ONLY ALICE CLAIMS]")
pool.claim_single(alice)

# Step 4: New borrower pays another 100 USDC
pool.distribute_reward(100)

# Step 5: Now both Alice and Bob claim
print("\n[ALICE AND BOB CLAIM AGAIN]")
pool.claim_all()
