/*
Run this script in Azure SQL Database: dabdemo
Server: sql-dabmcp-kwcm0e.database.windows.net
*/

SET NOCOUNT ON;

IF OBJECT_ID(N'dbo.OrderItems', N'U') IS NOT NULL DROP TABLE dbo.OrderItems;
IF OBJECT_ID(N'dbo.SalesOrders', N'U') IS NOT NULL DROP TABLE dbo.SalesOrders;
IF OBJECT_ID(N'dbo.Products', N'U') IS NOT NULL DROP TABLE dbo.Products;
IF OBJECT_ID(N'dbo.Customers', N'U') IS NOT NULL DROP TABLE dbo.Customers;
GO

CREATE TABLE dbo.Customers
(
    CustomerId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Customers PRIMARY KEY,
    FirstName nvarchar(80) NOT NULL,
    LastName nvarchar(80) NOT NULL,
    Email nvarchar(256) NOT NULL,
    City nvarchar(100) NOT NULL,
    CreatedAtUtc datetime2(0) NOT NULL CONSTRAINT DF_Customers_CreatedAtUtc DEFAULT sysutcdatetime(),
    CONSTRAINT UQ_Customers_Email UNIQUE (Email)
);
GO

CREATE TABLE dbo.Products
(
    ProductId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Products PRIMARY KEY,
    Sku nvarchar(40) NOT NULL,
    Name nvarchar(160) NOT NULL,
    Category nvarchar(100) NOT NULL,
    UnitPrice decimal(10,2) NOT NULL,
    IsActive bit NOT NULL CONSTRAINT DF_Products_IsActive DEFAULT 1,
    CreatedAtUtc datetime2(0) NOT NULL CONSTRAINT DF_Products_CreatedAtUtc DEFAULT sysutcdatetime(),
    CONSTRAINT UQ_Products_Sku UNIQUE (Sku),
    CONSTRAINT CK_Products_UnitPrice CHECK (UnitPrice >= 0)
);
GO

CREATE TABLE dbo.SalesOrders
(
    SalesOrderId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_SalesOrders PRIMARY KEY,
    CustomerId int NOT NULL,
    OrderDateUtc datetime2(0) NOT NULL CONSTRAINT DF_SalesOrders_OrderDateUtc DEFAULT sysutcdatetime(),
    Status nvarchar(30) NOT NULL CONSTRAINT DF_SalesOrders_Status DEFAULT N'New',
    Notes nvarchar(500) NULL,
    CONSTRAINT FK_SalesOrders_Customers FOREIGN KEY (CustomerId) REFERENCES dbo.Customers(CustomerId),
    CONSTRAINT CK_SalesOrders_Status CHECK (Status IN (N'New', N'Paid', N'Shipped', N'Cancelled'))
);
GO

CREATE TABLE dbo.OrderItems
(
    OrderItemId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_OrderItems PRIMARY KEY,
    SalesOrderId int NOT NULL,
    ProductId int NOT NULL,
    Quantity int NOT NULL,
    UnitPrice decimal(10,2) NOT NULL,
    CONSTRAINT FK_OrderItems_SalesOrders FOREIGN KEY (SalesOrderId) REFERENCES dbo.SalesOrders(SalesOrderId),
    CONSTRAINT FK_OrderItems_Products FOREIGN KEY (ProductId) REFERENCES dbo.Products(ProductId),
    CONSTRAINT CK_OrderItems_Quantity CHECK (Quantity > 0),
    CONSTRAINT CK_OrderItems_UnitPrice CHECK (UnitPrice >= 0)
);
GO

INSERT INTO dbo.Customers (FirstName, LastName, Email, City)
VALUES
    (N'Asha', N'Rao', N'asha.rao@example.com', N'Denver'),
    (N'Mateo', N'Garcia', N'mateo.garcia@example.com', N'Boulder'),
    (N'Noor', N'Khan', N'noor.khan@example.com', N'Aurora');

INSERT INTO dbo.Products (Sku, Name, Category, UnitPrice)
VALUES
    (N'DAB-BOOK-001', N'Data API Builder Field Guide', N'Books', 39.00),
    (N'DAB-MUG-001', N'DAB Coffee Mug', N'Merch', 14.50),
    (N'AZ-SQL-001', N'Azure SQL Notebook', N'Stationery', 9.99),
    (N'ACA-STICKER-001', N'Container Apps Sticker Pack', N'Merch', 5.00);

INSERT INTO dbo.SalesOrders (CustomerId, Status, Notes)
VALUES
    (1, N'Paid', N'First test order'),
    (2, N'New', N'Awaiting payment'),
    (1, N'Shipped', N'Shipped via standard delivery');

INSERT INTO dbo.OrderItems (SalesOrderId, ProductId, Quantity, UnitPrice)
VALUES
    (1, 1, 1, 39.00),
    (1, 2, 2, 14.50),
    (2, 3, 3, 9.99),
    (3, 4, 5, 5.00),
    (3, 2, 1, 14.50);
GO

CREATE OR ALTER VIEW dbo.CustomerOrderSummary
AS
SELECT
    c.CustomerId,
    c.FirstName,
    c.LastName,
    c.Email,
    c.City,
    COUNT(DISTINCT so.SalesOrderId) AS OrderCount,
    COALESCE(SUM(oi.Quantity * oi.UnitPrice), 0) AS TotalSpend
FROM dbo.Customers c
LEFT JOIN dbo.SalesOrders so ON so.CustomerId = c.CustomerId
LEFT JOIN dbo.OrderItems oi ON oi.SalesOrderId = so.SalesOrderId
GROUP BY c.CustomerId, c.FirstName, c.LastName, c.Email, c.City;
GO

CREATE OR ALTER PROCEDURE dbo.SearchProducts
    @search nvarchar(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT ProductId, Sku, Name, Category, UnitPrice, IsActive
    FROM dbo.Products
    WHERE
        IsActive = 1
        AND (
            @search IS NULL
            OR Name LIKE N'%' + @search + N'%'
            OR Category LIKE N'%' + @search + N'%'
            OR Sku LIKE N'%' + @search + N'%'
        )
    ORDER BY Name;
END;
GO

SELECT 'Customers' AS ObjectName, COUNT(*) AS RowCount FROM dbo.Customers
UNION ALL SELECT 'Products', COUNT(*) FROM dbo.Products
UNION ALL SELECT 'SalesOrders', COUNT(*) FROM dbo.SalesOrders
UNION ALL SELECT 'OrderItems', COUNT(*) FROM dbo.OrderItems;
GO
