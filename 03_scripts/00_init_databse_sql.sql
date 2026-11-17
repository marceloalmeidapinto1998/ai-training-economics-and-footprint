-- ============================================================================
-- SCRIPT: 00_init_database.sql
-- DESCRIPTION: Initializes the EpochAI_DW Data Warehouse database in SQL Server
-- ============================================================================

USE master;
GO

-- Create the database only if it does not already exist
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'EpochAI_DW')
BEGIN
    CREATE DATABASE EpochAI_DW;
    PRINT 'Database EpochAI_DW created successfully.';
END
ELSE
BEGIN
    PRINT 'Database EpochAI_DW already exists.';
END
GO

-- Switch context to the project database
USE EpochAI_DW;
GO