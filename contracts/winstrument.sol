contract Winstrument {

    // Nuking enums to get stack depth under control
    enum UnderlierType {gasLimit, difficulty, accountBalance, scalar}
    enum Operator {LT, GT, EQ, NEQ, LEQ, GEQ}
    
    struct Underlier {
        bytes32         utype;
        address         addressValue;
        int             coeffValue;
    }

    struct Conditional {
        Underlier       lhs;        // temporarily changed from an array of Underliers
        Underlier       rhs;        // temporarily changed from an array of Underliers
        bytes32         operator;
    //  uint            maturity;   // block number to use as maturity (temporarily disabled)
    }
    
    struct Conjunction {
        Conditional[]   conditionals;
    }
    
    struct OneToOneTransaction {
        address     sender;     // the person putting up the stake
        address     receiver;   // the person who stands to gain the stake
        uint        value;      // the stake
    }
   
    // State variables
    bool                _isActive;
    bool                _isComplete;
    Conjunction[]       _condition;
    OneToOneTransaction _transaction;
    uint                _maturity;
   
    function Instrument(){}
    
    // The sender constructs the contract
    function initialize(
        address sender, 
        address receiver, 
        bytes32 lhsUnderlierType, 
        address lhsUnderlierAddress,
        int    lhsUnderlierValue,
        bytes32 rhsUnderlierType, 
        address rhsUnderlierAddress,
        int    rhsUnderlierValue,
        bytes32 operator, 
        uint    maturity) returns (bool val) {
            
        _isActive = false;
        _isComplete = false;
        _maturity = maturity;
        _transaction = OneToOneTransaction(sender, receiver, msg.value);
        
        addCondition('OR',
                     lhsUnderlierType, lhsUnderlierAddress, lhsUnderlierValue,
                     rhsUnderlierType, rhsUnderlierAddress, rhsUnderlierValue,
                     operator);
        return true;
    }

    function addCondition(
        bytes32 logicalOperator,
        bytes32 lhsUnderlierType, 
        address lhsUnderlierAddress,
        int     lhsUnderlierValue,
        bytes32 rhsUnderlierType, 
        address rhsUnderlierAddress,
        int     rhsUnderlierValue,
        bytes32 inequalityOperator
        ) returns (bool) {
        
        Underlier lhs;
        lhs.utype = lhsUnderlierType;
        lhs.addressValue = lhsUnderlierAddress;
        lhs.coeffValue = lhsUnderlierValue;
        
        Underlier rhs;
        rhs.utype = rhsUnderlierType;
        rhs.addressValue = rhsUnderlierAddress;
        rhs.coeffValue = rhsUnderlierValue;
        
        Conditional conditional;
        conditional.lhs = lhs;
        conditional.rhs = rhs;
        conditional.operator = inequalityOperator;
        
        uint i = _condition.length;
        if (logicalOperator == 'AND') {
            // Add to last conjunction
            i -= 1;
            uint j = _condition[i].conditionals.length;
            _condition[i].conditionals.length = j + 1;
            _condition[i].conditionals[j] = conditional;
        } else if (logicalOperator == 'OR') {
            // Create new conjunction
            _condition.length += 1;
            _condition[i].conditionals.length = 1;
            _condition[i].conditionals[0] = conditional;
        } else {
            log1("Weird logical operator", logicalOperator);
        }
        return true;
    }
    
    function makeUnderlier(
        bytes32 lhsUnderlierType, 
        address lhsUnderlierAddress,
        int     lhsUnderlierValue
        ) private returns (Underlier) {
            
        Underlier lhs;
        lhs.utype = lhsUnderlierType;
        lhs.addressValue = lhsUnderlierAddress;
        lhs.coeffValue = lhsUnderlierValue;
        
        return lhs;
        }
    
    // The receiver validates the contract with the same parameters
    function validate() returns (bool val) {
        
        // Disabling validation until compound conditions are implemented.
        // Life is too cumbersome otherwise.
        
        _isActive == true;
        return true;
    }
    
    // If not validated, allow sender to withdraw
    function withdraw() returns (bool val) {
        if(_isActive) {
            return false;
        }
        suicide(_transaction.sender);
        _transaction.sender.send(this.balance);
        return true;
    }
    
    // If condition is met on maturity, allow receiver to claim from escrow
    function trigger() returns (bool val) {
        if (!isConditionMet()) {
            return false;
        }
        _isActive = false;
        _isComplete = true;
        _transaction.receiver.send(this.balance);
        return true;
    }
    
    // If condition is not met on maturity, allow sender to reclaim from escrow
    function recall() returns (bool val) {
        if (isConditionMet()) {
            return false;
        }
        _isActive = false;
        _isComplete = true;
        _transaction.sender.send(this.balance);
        return true;
    }
    
    // ===== Utility functions ===== //
    
    function strToOperator(bytes32 str) private returns (Operator) {
        if(str=='NEQ') {
            return Operator.NEQ;
        } else if(str=='LEQ') {
            return Operator.LEQ;
        } else if(str=='GEQ') {
            return Operator.GEQ;
        } else if(str=='GT') {
           return Operator.GT;
        } else if(str=='LT') {
            return Operator.LT;
        } else {
            return Operator.EQ;
        }
    }
    
    function strToUnderlierType(bytes32 str) private returns (UnderlierType) {
        if (str=='GASLIMIT') {
            return UnderlierType.gasLimit;
        } else if (str=='DIFFICULTY'){
            return UnderlierType.difficulty;
        } else if (str=='ACCBALANCE'){
            return UnderlierType.accountBalance;
        } else {
            return UnderlierType.scalar;
        }
    }
    
    // Resolve a single underlier to a value
    function resolveUnderlier(Underlier underlier) private returns (int) {
        int resolvedValue = 0;
        if (underlier.utype == 'GASLIMIT') {                    // UnderlierType.gasLimit) {
            resolvedValue = int(block.gaslimit);
        } else if(underlier.utype == 'DIFFICULTY') {            // UnderlierType.difficulty) {
            resolvedValue = int(block.difficulty);
        } else if(underlier.utype == 'ACCBALANCE') {            // UnderlierType.accountBalance) {
            resolvedValue = int(underlier.addressValue.balance);
        } else {
            resolvedValue = 1;
        }
        
        if (underlier.coeffValue != 0) {
            return underlier.coeffValue * resolvedValue;
        } else {
            // An uninitialized coeff will be set to 0
            return resolvedValue;
        }
    }
    
    function sumUnderliers(Underlier[] underliers) private returns (int) {
        int sum = 0;
        for (uint8 i = 0; i < underliers.length; ++i) {
            sum += resolveUnderlier(underliers[i]);
        }
        return sum;
    }
    
    // Sum up the resolved LHS and RHS of the conditional and check it
    function checkConditional(Conditional conditional) private returns (bool) {
        // per-conditional maturity is temporarily disabled
    //  if(block.number < conditional.maturity) {
    //      log1("Conditional has not matured");
    //      return false;
    //  }
        
        // Disabling linear functions for now
        int lhsSum = resolveUnderlier(conditional.lhs);      // sumUnderliers(conditional.lhs);
        int rhsSum = resolveUnderlier(conditional.rhs);      // sumUnderliers(conditional.rhs);
        log1("LHS", bytes32(lhsSum));
        log1("RHS", bytes32(rhsSum));
        if ((conditional.operator == 'EQ' && lhsSum == rhsSum) ||
            (conditional.operator == 'NEQ' && lhsSum != rhsSum) ||
            (conditional.operator == 'GEQ' && lhsSum >= rhsSum) ||
            (conditional.operator == 'LEQ' && lhsSum <= rhsSum) ||
            (conditional.operator == 'GT' && lhsSum > rhsSum) ||
            (conditional.operator == 'LT' && lhsSum < rhsSum)) {
                return true;
            }
        return false;
    }
    
    function checkConjunction(Conditional[] conditionals) private returns (bool) {
        for (uint8 i = 0; i < conditionals.length; ++i) {
            if (checkConditional(conditionals[i]) == false) {
                return false;
            }
        }
        return true;
    }
    
    function isConditionMet() private returns (bool) {
        if(block.number < _maturity) {
            return false;
        }
        
        // A condition is a disjunction of conjunctions
        for (uint8 i = 0; i < _condition.length; ++i) {
            Conditional[] conditionals = _condition[i].conditionals;
            bool satisfied = false;
            for (uint8 j = 0; j < conditionals.length; ++j) {
                if (checkConditional(conditionals[j]) == false) {
                    break;
                }
                return true;
            }
        }
        return false;
    }
}
