package com.example;

import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.io.PrintWriter;

@WebServlet(name = "OrdersServlet", urlPatterns = {"/api/orders/*"})
public class OrdersServlet extends HttpServlet {

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        
        PrintWriter out = response.getWriter();
        
        try {
            String pathInfo = request.getPathInfo();
            String userId = pathInfo != null ? pathInfo.substring(1) : "unknown";
            
            // Simulate database calls
            DatabaseService dbService = new DatabaseService();
            String orders = dbService.getOrders(userId);
            
            // Simulate some processing time
            Thread.sleep(75);
            
            out.print(orders);
            response.setStatus(HttpServletResponse.SC_OK);
            
        } catch (Exception e) {
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            out.print("{\"error\": \"" + e.getMessage() + "\"}");
        } finally {
            out.flush();
        }
    }
}
