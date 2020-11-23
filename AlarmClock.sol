pragma solidity ^0.6.2;
pragma AbiHeader expire;
pragma AbiHeader pubkey;
pragma AbiHeader time;


interface IAlarmClient {
    function wakeUp() external;

    function lackOfFunds() external;
}

interface IPingPong {
    function ping() external;
}

contract AlarmClient is IAlarmClient {
    // Modified that allows public function to accept calls from the account owner only
    modifier onlyOwner {
        require(msg.pubkey() == tvm.pubkey(), 100);
        tvm.accept();
        _;
    }
    // Modifier that allows public function to accept all external calls.
    modifier alwaysAccept {
        tvm.accept();
        _;
    }

    function setAlarm(address alarmClock, uint32 unixtime, uint128 amount) public alwaysAccept {
        AlarmClock(alarmClock).setTimer{value : amount}(unixtime);
    }

    function wakeUp() public override {}

    function lackOfFunds() public override {}

    function returnAllMoney(address dest) public onlyOwner {
        selfdestruct(dest);
    }
}

contract PingPong is IPingPong {
    // Modified that allows public function to accept calls from the account owner only
    modifier onlyOwner {
        require(msg.pubkey() == tvm.pubkey(), 100);
        tvm.accept();
        _;
    }

    function ping() public override {
        AlarmClock(msg.sender).pong{value : msg.value}();
    }

    function returnAllMoney(address dest) public onlyOwner {
        selfdestruct(dest);
    }
}


contract AlarmClock {
    // Modifier that allows public function to accept all external calls.
    modifier alwaysAccept {
        tvm.accept();
        _;
    }
    // Modified that allows public function to accept calls from the account owner only
    modifier onlyOwner {
        require(msg.pubkey() == tvm.pubkey(), 100);
        tvm.accept();
        _;
    }

    constructor(address pingPong) public onlyOwner {
        _pingPongAddress = pingPong;
        _currentTime = now;
        _lastBalance = address(this).balance;
    }

    //Due to the modifier onlyOwner function returnAllMoney can be called only by the owner of the contract.
    //Function returnAllMoney send all contract's money to dest_addr.
    function returnAllMoney(address dest) public onlyOwner {
        selfdestruct(dest);
    }

    //    onBounce(TvmSlice body) external {
    //    }
    //    onTickTock(bool isTock) external {
    //    }


    struct Alert {
        uint id;
        uint alarmTime;
        uint128 balance;
    }

    struct AlertToShow {
        uint id;
        uint addr;    // to show only - then delete it
        uint alarmTime;
        uint money;
    }

    address _pingPongAddress;

    uint128 public _lastBalance;
    uint32 public _currentTime;
    uint128 public _minimalAmount = 1;

    uint128 public _numberOfRecords = 0;
    address[] public _alertTableAddress;
    mapping(address => Alert) _alertTable;
    uint public _deletedRecords = 0;
    uint numberOfPingPongInProgress = 0;

    function setTimer(uint32 unixtime) public {
        // Check minimalAmount or return error(do not accept).
        require(msg.value >= _minimalAmount, 100);
        _lastBalance += msg.value;

        // Checking whether this element already exists
        if (_alertTable[msg.sender].alarmTime > 0) {
            // If it is, changing time and adding money
            _alertTable[msg.sender].alarmTime = unixtime;
            _alertTable[msg.sender].balance = _alertTable[msg.sender].balance + msg.value - _minimalAmount;
        } else {
            // If it doesn't, adding a new alarm record to the table
            _alertTableAddress.push(msg.sender);
            _numberOfRecords++;
            // and to the mapping
            _alertTable[msg.sender].id = _alertTableAddress.length;
            _alertTable[msg.sender].alarmTime = unixtime;
            _alertTable[msg.sender].balance = msg.value - _minimalAmount;
        }
        // Checking that we did succeed in adding a record or raise an error (do not accept).
        require(_alertTable[msg.sender].alarmTime == unixtime, 101);
        // TODO: return error message
        tvm.accept();
        // calling ping method
        ping();
    }

    function ping() internal {
        if (numberOfPingPongInProgress > 0) {
            return;
        }
        numberOfPingPongInProgress++;
        // sending money to PingPong contract which should be in other shardchain
        IPingPong(_pingPongAddress).ping();
    }

    // Called by PingPong contract only or in case of bounce
    // Receives money, counts the costs from the last call and spreads them across the table
    function pong() public {
        numberOfPingPongInProgress--;
        _currentTime = now;

        // count expenses
        uint128 expenses = _lastBalance - address(this).balance;
        _lastBalance = address(this).balance;

        // going through the table
        for (uint i = 0; i < _alertTableAddress.length; i++) {
            Alert currentRecord = _alertTable[_alertTableAddress[i]];

            // Are there records with alarm <= current time
            if (currentRecord.alarmTime < _currentTime) {
                // if they are, call wakeUp for every
                wakeUp(i);
            } else {
                // Client account balance
                currentRecord.balance -= expenses / _numberOfRecords;
                // if amount <= minimal amount then call lackOfFunds with remaining balance
                if (currentRecord.balance < _minimalAmount) {
                    lackOfFunds(i);
                }
            }
        }
        if (numberOfPingPongInProgress < 1 && _numberOfRecords > 0) {
            ping();
        }
        // TODO: compress the table, if _deletedRecords > some threshold
    }

    // waking up client
    function wakeUp(uint index) internal {
        address dest = _alertTableAddress[index];

        // Call method wakeUp of the client contract. The method name is fixed yet - "wakeUp"
        IAlarmClient(dest).wakeUp();

        // returns the remaining balance
        AlarmClient(dest).wakeUp{value : _alertTable[dest].balance}();

        deleteClientRecord(index);
    }

    // called in case of lack of funds on the client balance
    function lackOfFunds(uint index) internal {
        address dest = _alertTableAddress[index];

        // Call method lackOfFunds of the client contract.
        IAlarmClient(dest).lackOfFunds();

        // returns the remaining balance
        AlarmClient(dest).lackOfFunds{value : _alertTable[dest].balance}();

        deleteClientRecord(index);
    }

    // deletes the record from the tables
    function deleteClientRecord(uint index) internal {
        delete _alertTable[_alertTableAddress[index]];
        delete _alertTableAddress[index];
        _deletedRecords++;
        _numberOfRecords--;
    }

    // Replenishes the reserve fund
    function reserve(address dest, uint128 amount) external onlyOwner {
        //        dest.send(amount);
        dest.transfer(amount);
    }

    function SetMinimalAmount(uint128 minimalAmount) external onlyOwner {
        // change minimal amount to receive requests with
        _minimalAmount = minimalAmount;
    }

    function getData() public onlyOwner view returns (
        uint32 timestamp,
        uint minimalAmount,
        uint tableLength,
        address[] alertTableAddress,
        uint deletedRecords
    ) {
        timestamp = _currentTime;
        minimalAmount = _minimalAmount;
        tableLength = _numberOfRecords;
        alertTableAddress = _alertTableAddress;
        deletedRecords = _deletedRecords;
    }

    function getAlertTable() public onlyOwner view returns (Alert[] alertTable) {
        //        AlertToShow record;
        for (uint i = 0; i < _alertTableAddress.length; i++) {
            //            address addr = _alertTableAddress[i];
            //            record.id = i;
            //            record.addr = uint256(_alertTableAddress[i]);
            //            record.alarmTime = _alertTable[addr].alarmTime;
            //            record.money = _alertTable[addr].money;
            //            alertTable.push(record);
            alertTable.push(_alertTable[_alertTableAddress[i]]);
        }
    }
}
