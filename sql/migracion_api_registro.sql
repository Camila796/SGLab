-- Para bases ya creadas (volumen de Docker existente). Se aplica una sola vez:
--   docker exec -i sglab_db mysql -uroot -proot_password_123 < sql/migracion_api_registro.sql
USE bddsglab6;

-- Los seriales reales de BIOS son alfanuméricos. El índice UNIQUE existente se conserva.
ALTER TABLE Equipos MODIFY serialNumber VARCHAR(100);

INSERT INTO Laboratorios (nombre, comentario)
SELECT 'Laboratorio 6', 'Laboratorio de la tecnicatura'
WHERE NOT EXISTS (SELECT 1 FROM Laboratorios WHERE nombre = 'Laboratorio 6');
