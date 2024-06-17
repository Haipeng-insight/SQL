-- Survival analysis estimates how long it takes for a particular event to happen.
-- A customer starts; when will that customer stop? By assuming that the future will be similar to the past (the homogeneity assumption)

-- This analysis is starting with the hazard,
-- Then moving to survival, and then extracting useful measures from the survival probabilities. 
-- The final showcase is using survival analysis to estimate customer value, or at least estimate future revenue

-- The data is from a fictional mobile phone company that sells mobile phone in three markets.
-- The data is in the form of a transaction log, with one row per transaction.
-- The table used in the analysis is subs, which contains the following columns:
-- customer_id: a unique identifier for each customer
-- start_date: the date the customer started
-- stop_date: the date the customer stopped
-- stop_type: the reason the customer stopped, null or empty if the customer is still active
-- market: the market the customer is in
-- channel: the channel the customer was acquired through
-- monthly_fee: the monthly fee the customer is paying
-- tenure: the number of days the customer has been a customer
