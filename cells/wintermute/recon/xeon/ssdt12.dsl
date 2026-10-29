/*
 * Intel ACPI Component Architecture
 * AML/ASL+ Disassembler version 20260408 (64-bit version)
 * Copyright (c) 2000 - 2026 Intel Corporation
 * 
 * Disassembling to symbolic ASL+ operators
 *
 * Disassembly of ssdt12.dat
 *
 * Original Table Header:
 *     Signature        "SSDT"
 *     Length           0x0000006A (106)
 *     Revision         0x02
 *     Checksum         0xDF
 *     OEM ID           "SgRef"
 *     OEM Table ID     "SgPeg"
 *     OEM Revision     0x00001000 (4096)
 *     Compiler ID      "INTL"
 *     Compiler Version 0x20160422 (538313762)
 */
DefinitionBlock ("", "SSDT", 2, "SgRef", "SgPeg", 0x00001000)
{
    External (_SB_.PCI0.PEG0.PEGP, DeviceObj)
    External (GBAS, UnknownObj)
    External (SGGP, UnknownObj)
    External (SGMD, UnknownObj)

    Scope (\_SB.PCI0.PEG0.PEGP)
    {
    }
}

