-- Dealer stock table
CREATE TABLE IF NOT EXISTS dealer_stock (
    id INT AUTO_INCREMENT PRIMARY KEY,
    model VARCHAR(50) NOT NULL UNIQUE,
    stock INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Optional: seed some models (adjust models to those you actually have)
-- INSERT INTO dealer_stock (model, stock) VALUES ('asbo', 3) ON DUPLICATE KEY UPDATE stock = VALUES(stock);
