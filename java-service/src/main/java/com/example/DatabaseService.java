package com.example;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;

public class DatabaseService {
    
    private static final String DB_URL = "jdbc:h2:mem:testdb";
    private static final String USER = "sa";
    private static final String PASS = "";
    
    static {
        try {
            Class.forName("org.h2.Driver");
            initDatabase();
        } catch (Exception e) {
            System.err.println("Failed to initialize database: " + e.getMessage());
        }
    }
    
    private static void initDatabase() {
        try (Connection conn = DriverManager.getConnection(DB_URL, USER, PASS);
             Statement stmt = conn.createStatement()) {
            
            // Create users table
            stmt.execute("CREATE TABLE IF NOT EXISTS users (id INT PRIMARY KEY, name VARCHAR(255), email VARCHAR(255))");
            stmt.execute("INSERT INTO users VALUES (1, 'Alice', 'alice@example.com')");
            stmt.execute("INSERT INTO users VALUES (2, 'Bob', 'bob@example.com')");
            stmt.execute("INSERT INTO users VALUES (3, 'Charlie', 'charlie@example.com')");
            
            // Create orders table
            stmt.execute("CREATE TABLE IF NOT EXISTS orders (id INT PRIMARY KEY, user_id INT, product VARCHAR(255), amount DECIMAL(10,2))");
            stmt.execute("INSERT INTO orders VALUES (1, 1, 'Widget A', 29.99)");
            stmt.execute("INSERT INTO orders VALUES (2, 1, 'Widget B', 49.99)");
            stmt.execute("INSERT INTO orders VALUES (3, 2, 'Gadget X', 99.99)");
            
        } catch (Exception e) {
            System.err.println("Database initialization error: " + e.getMessage());
        }
    }
    
    public String getUsers() throws Exception {
        List<String> users = new ArrayList<String>();
        
        try (Connection conn = DriverManager.getConnection(DB_URL, USER, PASS);
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery("SELECT id, name, email FROM users")) {
            
            while (rs.next()) {
                users.add(String.format("{\"id\":%d,\"name\":\"%s\",\"email\":\"%s\"}", 
                    rs.getInt("id"), 
                    rs.getString("name"), 
                    rs.getString("email")));
            }
        }
        
        // Simulate second query
        Thread.sleep(20);
        
        return "{\"users\":[" + join(users, ",") + "]}";
    }
    
    public String getOrders(String userId) throws Exception {
        List<String> orders = new ArrayList<String>();
        
        try (Connection conn = DriverManager.getConnection(DB_URL, USER, PASS);
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery("SELECT id, product, amount FROM orders WHERE user_id = " + userId)) {
            
            while (rs.next()) {
                orders.add(String.format("{\"id\":%d,\"product\":\"%s\",\"amount\":%.2f}", 
                    rs.getInt("id"), 
                    rs.getString("product"), 
                    rs.getDouble("amount")));
            }
        }
        
        // Simulate second query for user details
        Thread.sleep(25);
        try (Connection conn = DriverManager.getConnection(DB_URL, USER, PASS);
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery("SELECT name FROM users WHERE id = " + userId)) {
            // Just execute, don't use result
            rs.next();
        }
        
        return "{\"orders\":[" + join(orders, ",") + "]}";
    }
    
    private String join(List<String> list, String delimiter) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < list.size(); i++) {
            sb.append(list.get(i));
            if (i < list.size() - 1) {
                sb.append(delimiter);
            }
        }
        return sb.toString();
    }
}
