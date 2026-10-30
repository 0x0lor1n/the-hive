" ACPI Source Language (iasl), incl. ASL 2.0 operators and the cpp layer
" coreboot runs over its .asl files. No treesitter grammar exists for ASL.
if exists("b:current_syntax")
  finish
endif

" ASL keywords are case-insensitive.
syn case ignore

syn keyword aslStructure DefinitionBlock Device Scope Method Name Alias External
syn keyword aslStructure Processor PowerResource ThermalZone OperationRegion
syn keyword aslStructure Field IndexField BankField Mutex Event Function
syn keyword aslStructure CreateBitField CreateByteField CreateWordField
syn keyword aslStructure CreateDWordField CreateQWordField CreateField
syn keyword aslType Package VarPackage Buffer ResourceTemplate
syn keyword aslConditional If ElseIf Else Switch Case Default
syn keyword aslRepeat While
syn keyword aslStatement Return Break Continue BreakPoint Noop Fatal

syn keyword aslFunction Store Notify Add Subtract Multiply Divide Mod And Or Xor
syn keyword aslFunction Not NAnd NOr ShiftLeft ShiftRight Increment Decrement
syn keyword aslFunction LAnd LOr LNot LEqual LGreater LLess LNotEqual
syn keyword aslFunction LGreaterEqual LLessEqual SizeOf DerefOf RefOf Index
syn keyword aslFunction Match Concatenate ConcatenateResTemplate CondRefOf
syn keyword aslFunction CopyObject ObjectType ToBuffer ToHexString
syn keyword aslFunction ToDecimalString ToInteger ToString ToBCD FromBCD
syn keyword aslFunction FindSetLeftBit FindSetRightBit Mid Acquire Release
syn keyword aslFunction Signal Wait Reset Sleep Stall Load LoadTable Unload
syn keyword aslFunction EisaId ToUUID ToPLD Unicode Printf Fprintf Timer

" Resource descriptor macros
syn keyword aslResource IO FixedIO Memory24 Memory32 Memory32Fixed DWordMemory
syn keyword aslResource QWordMemory ExtendedMemory WordIO DWordIO QWordIO
syn keyword aslResource ExtendedIO WordBusNumber WordSpace DWordSpace QWordSpace
syn keyword aslResource Interrupt IRQ IRQNoFlags DMA FixedDMA GpioInt GpioIo
syn keyword aslResource I2cSerialBus I2cSerialBusV2 SpiSerialBus SpiSerialBusV2
syn keyword aslResource UartSerialBus UartSerialBusV2 StartDependentFn
syn keyword aslResource StartDependentFnNoPri EndDependentFn Register
syn keyword aslResource VendorShort VendorLong PinFunction PinConfig PinGroup
syn keyword aslResource PinGroupFunction PinGroupConfig

syn keyword aslConstant Zero One Ones Revision Debug True False
syn keyword aslArg Arg0 Arg1 Arg2 Arg3 Arg4 Arg5 Arg6
syn keyword aslArg Local0 Local1 Local2 Local3 Local4 Local5 Local6 Local7

" Field/region/descriptor flags
syn keyword aslFlag ByteAcc WordAcc DWordAcc QWordAcc AnyAcc BufferAcc
syn keyword aslFlag Lock NoLock Preserve WriteAsOnes WriteAsZeros Offset AccessAs
syn keyword aslFlag SystemMemory SystemIO PCI_Config EmbeddedControl SMBus
syn keyword aslFlag SystemCMOS PciBarTarget IPMI GeneralPurposeIo
syn keyword aslFlag GenericSerialBus PCC FFixedHW PlatformRtMechanism
syn keyword aslFlag Serialized NotSerialized Decode10 Decode16
syn keyword aslFlag ResourceConsumer ResourceProducer MinFixed MinNotFixed
syn keyword aslFlag MaxFixed MaxNotFixed PosDecode SubDecode Cacheable
syn keyword aslFlag NonCacheable Prefetchable WriteCombining ReadWrite ReadOnly
syn keyword aslFlag Edge Level ActiveHigh ActiveLow ActiveBoth Exclusive Shared
syn keyword aslFlag ExclusiveAndWake SharedAndWake PullUp PullDown PullNone
syn keyword aslFlag PullDefault IoRestrictionNone IoRestrictionInputOnly
syn keyword aslFlag IoRestrictionOutputOnly IoRestrictionNoneAndPreserve
syn keyword aslFlag ControllerInitiated DeviceInitiated AddressingMode7Bit
syn keyword aslFlag AddressingMode10Bit ISAOnlyRanges NonISAOnlyRanges
syn keyword aslFlag EntireRange TypeTranslation TypeStatic SparseTranslation
syn keyword aslFlag DenseTranslation Compatibility TypeA TypeB TypeF BusMaster
syn keyword aslFlag NotBusMaster Transfer8 Transfer16 Transfer8_16
syn keyword aslFlag AddressRangeMemory AddressRangeReserved AddressRangeNVS
syn keyword aslFlag AddressRangeACPI MTR MEQ MLE MLT MGE MGT
syn keyword aslFlag UnknownObj IntObj StrObj BuffObj PkgObj FieldUnitObj
syn keyword aslFlag DeviceObj EventObj MethodObj MutexObj OpRegionObj
syn keyword aslFlag PowerResObj ProcessorObj ThermalZoneObj BuffFieldObj
syn keyword aslFlag DDBHandleObj

syn case match

" Reserved names (_HID, _CRS, _Q66, _L62) and namepath roots/separators
syn match aslReserved "\<_[A-Z0-9]\{1,3}\>"
syn match aslNamePath "[\\^]\+"
" coreboot/cpp macros: ALL_CAPS with an underscore (4-char ACPI names have none)
syn match aslMacro "\<[A-Z][A-Z0-9]*_[A-Z0-9_]*[A-Z0-9]\>"

syn match aslNumber "\<0[xX]\x\+\>"
syn match aslNumber "\<\d\+\>"
syn region aslString start=+"+ skip=+\\.+ end=+"+ contains=@Spell
syn region aslString start=+'+ skip=+\\.+ end=+'+

syn match aslOperator "[-+*/%&|^~!<>=]=\?\|&&\|||\|<<=\?\|>>=\?"

syn keyword aslTodo contained TODO FIXME XXX NOTE
syn region aslComment start="/\*" end="\*/" contains=aslTodo,@Spell
syn match aslComment "//.*$" contains=aslTodo,@Spell

syn region aslPreProc start="^\s*#\s*\(include\|define\|undef\|if\|ifdef\|ifndef\|elif\|else\|endif\|error\|pragma\)\>" skip="\\$" end="$" contains=aslString,aslComment
syn region aslInclude start="^\s*#\s*include\>" end="$" contains=aslString,aslIncluded
syn match aslIncluded contained "<[^>]*>"

hi def link aslStructure Structure
hi def link aslType Type
hi def link aslConditional Conditional
hi def link aslRepeat Repeat
hi def link aslStatement Statement
hi def link aslFunction Function
hi def link aslResource Function
hi def link aslConstant Constant
hi def link aslArg Identifier
hi def link aslFlag StorageClass
hi def link aslReserved Special
hi def link aslNamePath Delimiter
hi def link aslMacro Macro
hi def link aslNumber Number
hi def link aslString String
hi def link aslOperator Operator
hi def link aslTodo Todo
hi def link aslComment Comment
hi def link aslPreProc PreProc
hi def link aslInclude Include
hi def link aslIncluded String

let b:current_syntax = "asl"
