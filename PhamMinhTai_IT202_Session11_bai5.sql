-- =========================================================
-- [SÁNG TẠO] ĐIỀU PHỐI GIƯỜNG BỆNH TỰ ĐỘNG
-- =========================================================

-- =========================================================
-- PHẦN A: THIẾT KẾ KIẾN TRÚC
-- =========================================================

-- =========================================================
-- 1. FLOWCHART NGHIỆP VỤ
-- =========================================================

/*

[ Nurse Request ]
        |
        v
Receive Patient_ID + Dept_ID
        |
        v
+--------------------------------+
| CHECK 1: Dept_ID tồn tại ?     |
+--------------------------------+
        |
   NO -------> ERROR:
                 "Department not found"
        |
       YES
        |
        v
+--------------------------------+
| CHECK 2: Patient Completed ?   |
+--------------------------------+
        |
   YES -------> ERROR:
                 "Patient already discharged"
        |
       NO
        |
        v
CALL FindAvailableBed()
        |
        v
+--------------------------------+
| CHECK 3: Có giường trống ?     |
+--------------------------------+
        |
   NO -------> ERROR:
                 "Department is full"
                 KEEP OLD BED
        |
       YES
        |
        v
START TRANSACTION
        |
        v
Release Old Bed
        |
        v
Assign Patient To New Bed
        |
        v
COMMIT
        |
        v
Return New Bed_ID + Success Message

*/

-- =========================================================
-- 2. THIẾT KẾ GIAO TIẾP PROCEDURE
-- =========================================================

-- Procedure Master:
-- TransferPatientBed()

-- Procedure Child:
-- FindAvailableBed()

-- Giao tiếp dữ liệu:
-- Master truyền Dept_ID bằng IN
-- Child trả Bed_ID bằng OUT

-- Ví dụ:
-- CALL FindAvailableBed(
--      p_dept_id,
--      v_new_bed_id
-- );

-- =========================================================
-- PHẦN B: TRIỂN KHAI CODE
-- =========================================================

-- =========================================================
-- BỔ SUNG CỘT STATUS CHO PATIENTS
-- =========================================================

ALTER TABLE Patients
ADD COLUMN status VARCHAR(20) DEFAULT 'Active';

-- =========================================================
-- DỮ LIỆU TEST
-- =========================================================

UPDATE Patients
SET status = 'Completed'
WHERE patient_id = 3;

-- =========================================================
-- TẠO THÊM GIƯỜNG TEST
-- =========================================================

INSERT INTO Beds (bed_id, dept_id, patient_id)
VALUES
(102, 1, NULL);

-- =========================================================
-- CHILD PROCEDURE
-- TÌM GIƯỜNG TRỐNG
-- =========================================================

DROP PROCEDURE IF EXISTS FindAvailableBed;

DELIMITER //

CREATE PROCEDURE FindAvailableBed(

    IN p_dept_id INT,
    OUT p_bed_id INT

)
BEGIN

    SELECT bed_id
    INTO p_bed_id
    FROM Beds
    WHERE dept_id = p_dept_id
      AND patient_id IS NULL
    LIMIT 1;

END //

DELIMITER ;

-- =========================================================
-- MASTER PROCEDURE
-- ĐIỀU PHỐI CHUYỂN GIƯỜNG
-- =========================================================

DROP PROCEDURE IF EXISTS TransferPatientBed;

DELIMITER //

CREATE PROCEDURE TransferPatientBed(

    IN p_patient_id INT,
    IN p_target_dept_id INT,

    OUT p_new_bed_id INT,
    OUT p_message VARCHAR(255)

)
BEGIN

    DECLARE v_old_bed_id INT;
    DECLARE v_patient_status VARCHAR(20);
    DECLARE v_department_name VARCHAR(100);
    DECLARE v_department_count INT DEFAULT 0;

    -- =====================================
    -- CHECK DEPARTMENT TỒN TẠI
    -- =====================================

    SELECT COUNT(*)
    INTO v_department_count
    FROM Departments
    WHERE dept_id = p_target_dept_id;

    IF v_department_count = 0 THEN

        SET p_new_bed_id = NULL;
        SET p_message = 'Error: Department does not exist';

    ELSE

        -- =================================
        -- LẤY TÊN KHOA
        -- =================================

        SELECT dept_name
        INTO v_department_name
        FROM Departments
        WHERE dept_id = p_target_dept_id;

        -- =================================
        -- CHECK PATIENT STATUS
        -- =================================

        SELECT status
        INTO v_patient_status
        FROM Patients
        WHERE patient_id = p_patient_id;

        IF v_patient_status = 'Completed' THEN

            SET p_new_bed_id = NULL;
            SET p_message = 'Error: Patient already discharged';

        ELSE

            -- =============================
            -- TÌM GIƯỜNG TRỐNG
            -- =============================

            CALL FindAvailableBed(
                p_target_dept_id,
                p_new_bed_id
            );

            -- =============================
            -- KHÔNG CÒN GIƯỜNG
            -- =============================

            IF p_new_bed_id IS NULL THEN

                SET p_message =
                    CONCAT(
                        'Rejected: Department ',
                        v_department_name,
                        ' has no available bed'
                    );

            ELSE

                -- =========================
                -- LẤY GIƯỜNG CŨ
                -- =========================

                SELECT bed_id
                INTO v_old_bed_id
                FROM Beds
                WHERE patient_id = p_patient_id
                LIMIT 1;

                -- =========================
                -- TRANSACTION
                -- =========================

                START TRANSACTION;

                    -- Release old bed
                    UPDATE Beds
                    SET patient_id = NULL
                    WHERE bed_id = v_old_bed_id;

                    -- Assign new bed
                    UPDATE Beds
                    SET patient_id = p_patient_id
                    WHERE bed_id = p_new_bed_id;

                COMMIT;

                SET p_message = 'Transfer completed successfully';

            END IF;

        END IF;

    END IF;

END //

DELIMITER ;

-- =========================================================
-- KIỂM THỬ
-- =========================================================

-- =========================================================
-- TEST 1: CHUYỂN KHOA THÀNH CÔNG
-- =========================================================

CALL TransferPatientBed(
    1,
    2,
    @new_bed_id,
    @message
);

SELECT @new_bed_id AS new_bed_id,
       @message AS message;

-- Mong muốn:
-- Thành công chuyển sang bed 201

-- =========================================================
-- TEST 2: BẪY HẾT GIƯỜNG
-- =========================================================

CALL TransferPatientBed(
    1,
    3,
    @new_bed_id,
    @message
);

SELECT @new_bed_id AS new_bed_id,
       @message AS message;

-- Mong muốn:
-- Rejected: Department Khoa ICU has no available bed

-- =========================================================
-- TEST 3: BỆNH NHÂN ĐÃ XUẤT VIỆN
-- =========================================================

CALL TransferPatientBed(
    3,
    1,
    @new_bed_id,
    @message
);

SELECT @new_bed_id AS new_bed_id,
       @message AS message;

-- Mong muốn:
-- Error: Patient already discharged

-- =========================================================
-- TEST 4: KHOA KHÔNG TỒN TẠI
-- =========================================================

CALL TransferPatientBed(
    1,
    999,
    @new_bed_id,
    @message
);

SELECT @new_bed_id AS new_bed_id,
       @message AS message;

-- Mong muốn:
-- Error: Department does not exist