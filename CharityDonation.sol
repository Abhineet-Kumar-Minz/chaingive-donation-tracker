// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title CharityDonationTracker
 * @dev A transparent, on-chain charity donation tracking system
 */
contract CharityDonationTracker {

    address public owner;
    uint256 public charityCount;
    uint256 public donationCount;

    struct Charity {
        uint256 id;
        string name;
        string description;
        string category;
        address payable walletAddress;
        bool isActive;
        uint256 totalReceived;
        uint256 donorCount;
        uint256 createdAt;
    }

    struct Donation {
        uint256 id;
        address donor;
        uint256 charityId;
        uint256 amount;
        string message;
        uint256 timestamp;
        bool refunded;
    }

    mapping(uint256 => Charity) public charities;
    mapping(uint256 => Donation) public donations;
    mapping(address => uint256[]) public donorHistory;
    mapping(uint256 => uint256[]) public charityDonations;
    mapping(uint256 => mapping(address => bool)) public hasDonated;

    event CharityAdded(uint256 indexed id, string name, address walletAddress, uint256 timestamp);
    event CharityUpdated(uint256 indexed id, string name, bool isActive);
    event DonationMade(uint256 indexed donationId, address indexed donor, uint256 indexed charityId, uint256 amount, uint256 timestamp);
    event FundsWithdrawn(uint256 indexed charityId, address recipient, uint256 amount, uint256 timestamp);
    event RefundIssued(uint256 indexed donationId, address donor, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this");
        _;
    }

    modifier charityExists(uint256 _charityId) {
        require(_charityId > 0 && _charityId <= charityCount, "Charity does not exist");
        _;
    }

    modifier charityActive(uint256 _charityId) {
        require(charities[_charityId].isActive, "Charity is not active");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    // ─── CHARITY MANAGEMENT ───────────────────────────────────────────────────

    function addCharity(
        string memory _name,
        string memory _description,
        string memory _category,
        address payable _walletAddress
    ) external onlyOwner returns (uint256) {
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(_walletAddress != address(0), "Invalid wallet address");

        charityCount++;
        charities[charityCount] = Charity({
            id: charityCount,
            name: _name,
            description: _description,
            category: _category,
            walletAddress: _walletAddress,
            isActive: true,
            totalReceived: 0,
            donorCount: 0,
            createdAt: block.timestamp
        });

        emit CharityAdded(charityCount, _name, _walletAddress, block.timestamp);
        return charityCount;
    }

    function updateCharity(
        uint256 _charityId,
        string memory _name,
        string memory _description,
        string memory _category,
        bool _isActive
    ) external onlyOwner charityExists(_charityId) {
        Charity storage c = charities[_charityId];
        c.name = _name;
        c.description = _description;
        c.category = _category;
        c.isActive = _isActive;

        emit CharityUpdated(_charityId, _name, _isActive);
    }

    function deactivateCharity(uint256 _charityId) external onlyOwner charityExists(_charityId) {
        charities[_charityId].isActive = false;
        emit CharityUpdated(_charityId, charities[_charityId].name, false);
    }

    // ─── DONATIONS ────────────────────────────────────────────────────────────

    function donate(
        uint256 _charityId,
        string memory _message
    ) external payable charityExists(_charityId) charityActive(_charityId) {
        require(msg.value > 0, "Donation must be greater than 0");

        donationCount++;
        Charity storage c = charities[_charityId];

        donations[donationCount] = Donation({
            id: donationCount,
            donor: msg.sender,
            charityId: _charityId,
            amount: msg.value,
            message: _message,
            timestamp: block.timestamp,
            refunded: false
        });

        if (!hasDonated[_charityId][msg.sender]) {
            hasDonated[_charityId][msg.sender] = true;
            c.donorCount++;
        }

        c.totalReceived += msg.value;
        donorHistory[msg.sender].push(donationCount);
        charityDonations[_charityId].push(donationCount);

        // Forward ETH directly to charity wallet
        c.walletAddress.transfer(msg.value);

        emit DonationMade(donationCount, msg.sender, _charityId, msg.value, block.timestamp);
        emit FundsWithdrawn(_charityId, c.walletAddress, msg.value, block.timestamp);
    }

    // ─── READ FUNCTIONS ───────────────────────────────────────────────────────

    function getCharity(uint256 _charityId)
        external
        view
        charityExists(_charityId)
        returns (Charity memory)
    {
        return charities[_charityId];
    }

    function getAllCharities() external view returns (Charity[] memory) {
        Charity[] memory result = new Charity[](charityCount);
        for (uint256 i = 1; i <= charityCount; i++) {
            result[i - 1] = charities[i];
        }
        return result;
    }

    function getDonation(uint256 _donationId) external view returns (Donation memory) {
        require(_donationId > 0 && _donationId <= donationCount, "Donation does not exist");
        return donations[_donationId];
    }

    function getDonorHistory(address _donor) external view returns (uint256[] memory) {
        return donorHistory[_donor];
    }

    function getCharityDonations(uint256 _charityId)
        external
        view
        charityExists(_charityId)
        returns (uint256[] memory)
    {
        return charityDonations[_charityId];
    }

    function getTotalStats() external view returns (
        uint256 totalCharities,
        uint256 totalDonations,
        uint256 activeCharities
    ) {
        totalCharities = charityCount;
        totalDonations = donationCount;
        uint256 active = 0;
        for (uint256 i = 1; i <= charityCount; i++) {
            if (charities[i].isActive) active++;
        }
        activeCharities = active;
    }

    function getTopCharities(uint256 _limit) external view returns (Charity[] memory) {
        uint256 limit = _limit > charityCount ? charityCount : _limit;
        Charity[] memory all = new Charity[](charityCount);
        for (uint256 i = 0; i < charityCount; i++) {
            all[i] = charities[i + 1];
        }
        // Bubble sort descending by totalReceived
        for (uint256 i = 0; i < charityCount - 1; i++) {
            for (uint256 j = 0; j < charityCount - i - 1; j++) {
                if (all[j].totalReceived < all[j + 1].totalReceived) {
                    Charity memory temp = all[j];
                    all[j] = all[j + 1];
                    all[j + 1] = temp;
                }
            }
        }
        Charity[] memory result = new Charity[](limit);
        for (uint256 i = 0; i < limit; i++) {
            result[i] = all[i];
        }
        return result;
    }

    function getDonorTotalGiven(address _donor) external view returns (uint256 total) {
        uint256[] memory ids = donorHistory[_donor];
        for (uint256 i = 0; i < ids.length; i++) {
            if (!donations[ids[i]].refunded) {
                total += donations[ids[i]].amount;
            }
        }
    }
}
