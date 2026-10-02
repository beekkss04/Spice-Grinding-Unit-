-- Case Study 131 : Spice Grinding Unit Order Fulfilment (PostgreSQL)
-- Student : Bhaumik Keer   Roll No : 150096725030
 createdb spice_db 

-- ===================== SCHEMA =====================


CREATE TABLE blends (
    id               SERIAL        PRIMARY KEY,
    name             VARCHAR(60)   NOT NULL UNIQUE,
    city             VARCHAR(40)   NOT NULL,
    price_per_kg_rs  NUMERIC(8,2)  NOT NULL CHECK (price_per_kg_rs > 0),
    is_active        BOOLEAN       NOT NULL DEFAULT FALSE   -- derived, kept by trigger
);

CREATE TABLE production_batches (
    id           SERIAL       PRIMARY KEY,
    blend_id     INT          NOT NULL REFERENCES blends(id) ON DELETE RESTRICT,
    batch_date   DATE         NOT NULL,
    kg_produced  INT          NOT NULL CHECK (kg_produced > 0),
    status       VARCHAR(12)  NOT NULL DEFAULT 'COMPLETE' CHECK (status IN ('IN_PROGRESS','COMPLETE')),
    UNIQUE (id, blend_id)     -- lets dispatches reference (batch, blend) together
);

CREATE TABLE orders (
    id             SERIAL       PRIMARY KEY,
    customer_name  VARCHAR(60)  NOT NULL,
    blend_id       INT          NOT NULL REFERENCES blends(id) ON DELETE RESTRICT,
    kg_ordered     INT          NOT NULL CHECK (kg_ordered > 0),
    order_date     DATE         NOT NULL,
    UNIQUE (id, blend_id)
);

CREATE TABLE dispatches (
    id             SERIAL  PRIMARY KEY,
    blend_id       INT     NOT NULL REFERENCES blends(id) ON DELETE RESTRICT,
    kg_dispatched  INT     NOT NULL CHECK (kg_dispatched > 0),
    dispatch_date  DATE    NOT NULL,
    batch_id       INT     NOT NULL,
    order_id       INT     NOT NULL,
    FOREIGN KEY (batch_id, blend_id) REFERENCES production_batches (id, blend_id),
    FOREIGN KEY (order_id, blend_id) REFERENCES orders (id, blend_id)
);

CREATE INDEX idx_dispatches_blend ON dispatches (blend_id);
CREATE INDEX idx_dispatches_batch ON dispatches (batch_id);
CREATE INDEX idx_dispatches_order ON dispatches (order_id);
CREATE INDEX idx_dispatches_date  ON dispatches (dispatch_date);

-- Trigger 1: business rules that need other rows (batch complete, dates, stock and order limits)
CREATE FUNCTION check_dispatch() RETURNS trigger AS $$
DECLARE
    b        production_batches%ROWTYPE;
    o        orders%ROWTYPE;
    used_b   INT;
    used_o   INT;
BEGIN
    SELECT * INTO b FROM production_batches WHERE id = NEW.batch_id FOR UPDATE;  -- row lock
    IF NOT FOUND THEN RAISE EXCEPTION 'Batch % does not exist', NEW.batch_id; END IF;
    SELECT * INTO o FROM orders WHERE id = NEW.order_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order % does not exist', NEW.order_id; END IF;

    IF b.status <> 'COMPLETE' THEN
        RAISE EXCEPTION 'Batch % is not complete yet', b.id;
    END IF;
    IF NEW.dispatch_date < b.batch_date THEN
        RAISE EXCEPTION 'Dispatch date % is before batch date %', NEW.dispatch_date, b.batch_date;
    END IF;
    IF NEW.dispatch_date < o.order_date THEN
        RAISE EXCEPTION 'Dispatch date % is before order date %', NEW.dispatch_date, o.order_date;
    END IF;

    SELECT COALESCE(SUM(kg_dispatched),0) INTO used_b FROM dispatches
     WHERE batch_id = NEW.batch_id AND id IS DISTINCT FROM NEW.id;
    IF used_b + NEW.kg_dispatched > b.kg_produced THEN
        RAISE EXCEPTION 'Batch % has only % kg left, cannot dispatch % kg',
                        b.id, b.kg_produced - used_b, NEW.kg_dispatched;
    END IF;

    SELECT COALESCE(SUM(kg_dispatched),0) INTO used_o FROM dispatches
     WHERE order_id = NEW.order_id AND id IS DISTINCT FROM NEW.id;
    IF used_o + NEW.kg_dispatched > o.kg_ordered THEN
        RAISE EXCEPTION 'Order % has only % kg left to ship, cannot dispatch % kg',
                        o.id, o.kg_ordered - used_o, NEW.kg_dispatched;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_dispatch
    BEFORE INSERT OR UPDATE ON dispatches
    FOR EACH ROW EXECUTE FUNCTION check_dispatch();

-- Trigger 2: keeps the derived blends.is_active flag correct
CREATE FUNCTION refresh_is_active() RETURNS trigger AS $$
BEGIN
    IF TG_OP <> 'DELETE' THEN
        UPDATE blends SET is_active = EXISTS (SELECT 1 FROM dispatches WHERE blend_id = NEW.blend_id)
         WHERE id = NEW.blend_id;
    END IF;
    IF TG_OP <> 'INSERT' THEN
        UPDATE blends SET is_active = EXISTS (SELECT 1 FROM dispatches WHERE blend_id = OLD.blend_id)
         WHERE id = OLD.blend_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_refresh_is_active
    AFTER INSERT OR UPDATE OR DELETE ON dispatches
    FOR EACH ROW EXECUTE FUNCTION refresh_is_active();

-- ===================== SEED DATA =====================
-- Sample rows from the case study are included (dispatch 1 is dated 2024-01-15 instead of 2024-01-08,
-- because it was earlier than its batch). Dispatches are loaded last so the trigger validates them.
INSERT INTO blends (id, name, city, price_per_kg_rs) VALUES
  (1, 'Garam Masala', 'Jaipur', 1005),
  (2, 'Chilli Powder', 'Ahmedabad', 980),
  (3, 'Turmeric Powder', 'Chennai', 455),
  (4, 'Sambar Masala', 'Jaipur', 1080),
  (5, 'Kitchen King Masala', 'Bengaluru', 555),
  (6, 'Pav Bhaji Masala', 'Ahmedabad', 580),
  (7, 'Coriander Powder', 'Pune', 420),
  (8, 'Cumin Powder', 'Unjha', 690),
  (9, 'Chai Masala', 'Kolkata', 640),
  (10, 'Biryani Masala', 'Hyderabad', 890),
  (11, 'Chaat Masala', 'Delhi', 520),
  (12, 'Black Pepper Powder', 'Kochi', 1250);

INSERT INTO production_batches (id, blend_id, batch_date, kg_produced) VALUES
  (1, 1, '2024-01-12', 500),
  (2, 2, '2024-01-20', 350),
  (3, 1, '2024-02-05', 620),
  (4, 3, '2024-02-08', 400),
  (5, 4, '2024-02-25', 300),
  (6, 5, '2024-03-01', 500),
  (7, 6, '2024-03-04', 250),
  (8, 7, '2024-03-10', 450),
  (9, 8, '2024-03-15', 380),
  (10, 9, '2024-03-22', 300),
  (11, 10, '2024-04-02', 420),
  (12, 11, '2024-04-08', 350),
  (13, 12, '2024-04-15', 200),
  (14, 2, '2024-04-18', 600),
  (15, 3, '2024-05-06', 500),
  (16, 5, '2024-05-14', 450),
  (17, 10, '2024-05-20', 300),
  (18, 8, '2024-06-03', 400);

INSERT INTO orders (id, customer_name, blend_id, kg_ordered, order_date) VALUES
  (1, 'Sri Ram Traders', 1, 300, '2024-01-10'),
  (2, 'Annapurna Condiments', 2, 200, '2024-01-18'),
  (3, 'Sri Ram Traders', 1, 400, '2024-02-01'),
  (4, 'Sri Ram Traders', 1, 250, '2024-01-14'),
  (5, 'Annapurna Condiments', 2, 250, '2024-01-28'),
  (6, 'Mahalaxmi Stores', 3, 200, '2024-02-10'),
  (7, 'Mahalaxmi Stores', 3, 100, '2024-02-20'),
  (8, 'Spice Route Foods', 4, 80, '2024-02-28'),
  (9, 'Annapurna Condiments', 5, 280, '2024-03-05'),
  (10, 'Gujarat Retail Mart', 5, 150, '2024-03-20'),
  (11, 'Gujarat Retail Mart', 7, 200, '2024-03-12'),
  (12, 'Spice Route Foods', 7, 150, '2024-03-25'),
  (13, 'Mahalaxmi Stores', 8, 220, '2024-03-20'),
  (14, 'Sri Ram Traders', 9, 120, '2024-03-28'),
  (15, 'Annapurna Condiments', 10, 300, '2024-04-05'),
  (16, 'Gujarat Retail Mart', 11, 180, '2024-04-10'),
  (17, 'Spice Route Foods', 2, 300, '2024-04-20'),
  (18, 'Mahalaxmi Stores', 3, 250, '2024-05-08'),
  (19, 'Gujarat Retail Mart', 5, 300, '2024-05-16'),
  (20, 'Sri Ram Traders', 10, 100, '2024-05-22'),
  (21, 'Annapurna Condiments', 8, 250, '2024-06-05'),
  (22, 'Spice Route Foods', 1, 150, '2024-05-01'),
  (23, 'Sri Ram Traders', 4, 150, '2024-04-01'),
  (24, 'Mahalaxmi Stores', 7, 100, '2024-04-12'),
  (25, 'Mahalaxmi Stores', 9, 150, '2024-04-20'),
  (26, 'Gujarat Retail Mart', 12, 150, '2024-06-01'),
  (27, 'Sri Ram Traders', 6, 100, '2024-06-02'),
  (28, 'Spice Route Foods', 11, 120, '2024-04-25'),
  (29, 'Annapurna Condiments', 3, 150, '2024-05-20'),
  (30, 'Sri Ram Traders', 5, 100, '2024-06-01'),
  (31, 'Gujarat Retail Mart', 10, 200, '2024-05-25');

INSERT INTO dispatches (id, blend_id, kg_dispatched, dispatch_date, batch_id, order_id) VALUES
  (1, 1, 239, '2024-01-15', 1, 1),
  (2, 1, 248, '2024-01-19', 1, 4),
  (3, 2, 239, '2024-02-02', 2, 5),
  (4, 3, 194, '2024-02-14', 4, 6),
  (5, 3, 59, '2024-02-27', 4, 7),
  (6, 4, 59, '2024-03-05', 5, 8),
  (7, 5, 266, '2024-03-16', 6, 9),
  (8, 5, 149, '2024-03-28', 6, 10),
  (9, 1, 380, '2024-02-12', 3, 3),
  (10, 7, 180, '2024-03-18', 8, 11),
  (11, 8, 200, '2024-03-27', 9, 13),
  (12, 7, 150, '2024-03-30', 8, 12),
  (13, 9, 120, '2024-04-02', 10, 14),
  (14, 4, 140, '2024-04-05', 5, 23),
  (15, 10, 250, '2024-04-10', 11, 15),
  (16, 11, 180, '2024-04-16', 12, 16),
  (17, 7, 90, '2024-04-18', 8, 24),
  (18, 2, 120, '2024-04-22', 14, 2),
  (19, 9, 150, '2024-04-24', 10, 25),
  (20, 2, 300, '2024-04-25', 14, 17),
  (21, 11, 100, '2024-04-30', 12, 28),
  (22, 1, 150, '2024-05-03', 3, 22),
  (23, 3, 250, '2024-05-12', 15, 18),
  (24, 5, 300, '2024-05-22', 16, 19),
  (25, 3, 150, '2024-05-25', 15, 29),
  (26, 10, 100, '2024-05-28', 17, 20),
  (27, 10, 180, '2024-05-30', 17, 31),
  (28, 5, 90, '2024-06-06', 16, 30),
  (29, 8, 240, '2024-06-10', 18, 21);

SELECT setval(pg_get_serial_sequence('blends','id'), (SELECT MAX(id) FROM blends)),
       setval(pg_get_serial_sequence('production_batches','id'), (SELECT MAX(id) FROM production_batches)),
       setval(pg_get_serial_sequence('orders','id'), (SELECT MAX(id) FROM orders)),
       setval(pg_get_serial_sequence('dispatches','id'), (SELECT MAX(id) FROM dispatches));

-- ===================== PART : TRANSACTIONS, ACID AND CONCURRENCY =====================

-- Q01. Transaction: insert one dispatch (BEGIN ... COMMIT)
-- Name - Bhaumik Keer Roll No - 150096725030
BEGIN;
INSERT INTO dispatches (blend_id, kg_dispatched, dispatch_date, batch_id, order_id)
VALUES (6, 80, '2024-06-10', 7, 27);
SELECT id, blend_id, kg_dispatched, dispatch_date, batch_id, order_id
FROM dispatches WHERE order_id = 27;
COMMIT;

-- Q02. ROLLBACK: what it undoes
-- Name - Bhaumik Keer Roll No - 150096725030
BEGIN;
INSERT INTO dispatches (blend_id, kg_dispatched, dispatch_date, batch_id, order_id)
VALUES (11, 15, '2024-06-11', 12, 28);
SELECT COUNT(*) AS dispatches_for_order_28_inside_txn FROM dispatches WHERE order_id = 28;
ROLLBACK;
SELECT COUNT(*) AS dispatches_for_order_28_after_rollback FROM dispatches WHERE order_id = 28;

-- Q03. Lost update on dispatch 9 (kg_dispatched = 380)
-- Name - Bhaumik Keer Roll No - 150096725030
-- Session A: BEGIN; read 380
-- Session B: BEGIN; read 380
SELECT id, kg_dispatched FROM dispatches WHERE id = 9;
-- Session A: 380 + 10
UPDATE dispatches SET kg_dispatched = 390 WHERE id = 9;
-- Session B: 380 + 5, from its old read (then both COMMIT)
UPDATE dispatches SET kg_dispatched = 385 WHERE id = 9;
SELECT id, kg_dispatched AS final_value_lost_update FROM dispatches WHERE id = 9;
UPDATE dispatches SET kg_dispatched = 380 WHERE id = 9;

-- Q04. Fix for the lost update: FOR UPDATE + relative update
-- Name - Bhaumik Keer Roll No - 150096725030
-- Session A
BEGIN;
SELECT kg_dispatched FROM dispatches WHERE id = 9 FOR UPDATE;
UPDATE dispatches SET kg_dispatched = kg_dispatched + 10 WHERE id = 9;
COMMIT;
-- Session B (waits for A, then sees 390)
BEGIN;
SELECT kg_dispatched FROM dispatches WHERE id = 9 FOR UPDATE;
UPDATE dispatches SET kg_dispatched = kg_dispatched + 5 WHERE id = 9;
COMMIT;
SELECT id, kg_dispatched AS final_value_no_update_lost FROM dispatches WHERE id = 9;
UPDATE dispatches SET kg_dispatched = 380 WHERE id = 9;

-- Q05. SAVEPOINT inside a multi-step transaction
-- Name - Bhaumik Keer Roll No - 150096725030
BEGIN;
INSERT INTO dispatches (blend_id, kg_dispatched, dispatch_date, batch_id, order_id)
VALUES (2, 50, '2024-06-12', 14, 2);
SAVEPOINT after_dispatch;
UPDATE blends SET price_per_kg_rs = price_per_kg_rs * 10 WHERE id = 2;
SELECT id, name, price_per_kg_rs AS price_after_mistake FROM blends WHERE id = 2;
ROLLBACK TO SAVEPOINT after_dispatch;
SELECT id, name, price_per_kg_rs AS price_restored FROM blends WHERE id = 2;
COMMIT;
SELECT id, blend_id, kg_dispatched, dispatch_date FROM dispatches WHERE order_id = 2 ORDER BY id;

-- Q06. Isolation level for recording a dispatch: READ COMMITTED
-- Name - Bhaumik Keer Roll No - 150096725030
BEGIN ISOLATION LEVEL READ COMMITTED;
SHOW transaction_isolation;
INSERT INTO dispatches (blend_id, kg_dispatched, dispatch_date, batch_id, order_id)
VALUES (4, 10, '2024-06-13', 5, 8);
SELECT id, blend_id, kg_dispatched, dispatch_date FROM dispatches WHERE order_id = 8 ORDER BY id;
COMMIT;

-- Q07. New blend + its first dispatch as one atomic unit (success)
-- Name - Bhaumik Keer Roll No - 150096725030
BEGIN;
INSERT INTO blends (name, city, price_per_kg_rs) VALUES ('Tandoori Masala', 'Delhi', 760);
INSERT INTO production_batches (blend_id, batch_date, kg_produced)
VALUES (currval('blends_id_seq'), '2024-06-14', 200);
INSERT INTO orders (customer_name, blend_id, kg_ordered, order_date)
VALUES ('Spice Route Foods', currval('blends_id_seq'), 120, '2024-06-14');
INSERT INTO dispatches (blend_id, kg_dispatched, dispatch_date, batch_id, order_id)
VALUES (currval('blends_id_seq'), 100, '2024-06-15',
        currval('production_batches_id_seq'), currval('orders_id_seq'));
COMMIT;
SELECT b.id, b.name, b.is_active, d.kg_dispatched, d.dispatch_date
FROM blends b JOIN dispatches d ON d.blend_id = b.id WHERE b.name = 'Tandoori Masala';

-- Q08. Same atomic unit when the second insert fails (expected ERROR)
-- Name - Bhaumik Keer Roll No - 150096725030
BEGIN;
INSERT INTO blends (name, city, price_per_kg_rs) VALUES ('Peri Peri Masala', 'Mumbai', 640);
INSERT INTO production_batches (blend_id, batch_date, kg_produced)
VALUES (currval('blends_id_seq'), '2024-06-14', 100);
INSERT INTO orders (customer_name, blend_id, kg_ordered, order_date)
VALUES ('Spice Route Foods', currval('blends_id_seq'), 200, '2024-06-14');
INSERT INTO dispatches (blend_id, kg_dispatched, dispatch_date, batch_id, order_id)
VALUES (currval('blends_id_seq'), 150, '2024-06-15',
        currval('production_batches_id_seq'), currval('orders_id_seq'));
COMMIT;
SELECT COUNT(*) AS peri_peri_rows_left FROM blends WHERE name = 'Peri Peri Masala';

-- Q09. Derived is_active flag maintained by a trigger
-- Name - Bhaumik Keer Roll No - 150096725030
SELECT id, name, is_active AS before_insert FROM blends WHERE id = 12;
BEGIN;
INSERT INTO dispatches (blend_id, kg_dispatched, dispatch_date, batch_id, order_id)
VALUES (12, 100, '2024-06-16', 13, 26);
SELECT id, name, is_active AS after_insert_inside_txn FROM blends WHERE id = 12;
ROLLBACK;
SELECT id, name, is_active AS after_rollback FROM blends WHERE id = 12;


-- ===================== PART : REPORTING QUERIES ON THE FULL DATASET =====================

-- Q10. Filtering: dispatches of 150 kg or more in March-April 2024
-- Name - Bhaumik Keer Roll No - 150096725030
SELECT id, blend_id, kg_dispatched, dispatch_date
FROM dispatches
WHERE dispatch_date BETWEEN '2024-03-01' AND '2024-04-30'
  AND kg_dispatched >= 150
ORDER BY dispatch_date;

-- Q11. Join: dispatch with blend, customer and rupee value
-- Name - Bhaumik Keer Roll No - 150096725030
SELECT d.id AS dispatch_id, d.dispatch_date, b.name AS blend, o.customer_name,
       d.kg_dispatched, b.price_per_kg_rs, d.kg_dispatched * b.price_per_kg_rs AS value_rs
FROM dispatches d
JOIN blends b ON b.id = d.blend_id
JOIN orders o ON o.id = d.order_id
ORDER BY d.dispatch_date, d.id
LIMIT 15;

-- Q12. GROUP BY / HAVING: revenue per blend (300 kg or more)
-- Name - Bhaumik Keer Roll No - 150096725030
SELECT b.name, b.city, COUNT(d.id) AS dispatch_count,
       SUM(d.kg_dispatched) AS total_kg,
       SUM(d.kg_dispatched * b.price_per_kg_rs) AS revenue_rs
FROM blends b
JOIN dispatches d ON d.blend_id = b.id
GROUP BY b.id, b.name, b.city
HAVING SUM(d.kg_dispatched) >= 300
ORDER BY revenue_rs DESC;

-- Q13. Correlated subquery: dispatches above their own blend's average
-- Name - Bhaumik Keer Roll No - 150096725030
SELECT d.id, b.name, d.kg_dispatched, d.dispatch_date
FROM dispatches d
JOIN blends b ON b.id = d.blend_id
WHERE d.kg_dispatched > (SELECT AVG(d2.kg_dispatched)
                         FROM dispatches d2
                         WHERE d2.blend_id = d.blend_id)
ORDER BY b.name, d.kg_dispatched DESC;

