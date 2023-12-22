// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

/**
 * @title LinkedAddressList
 * @dev Library implementing a linked list structure to store and operate sorted Troves.
 */
library LinkedAddressList {
    struct EntryLink {
        address prev;
        address next;
    }

    struct List {
        address _last;
        address _first;
        uint256 _size;
        mapping(address => EntryLink) _values;
    }

    /**
     * @dev Adds an element to the linked list.
     * @param _list The storage pointer to the linked list.
     * @param _element The element to be added.
     * @param _reference The reference element to determine the position for addition.
     * @param _before A boolean indicating whether to add the element before the reference.
     * @return A boolean indicating the success of the addition.
     */
    function add(List storage _list, address _element, address _reference, bool _before) internal returns (bool) {
        require(
            _reference == address(0x0) || _list._values[_reference].next != address(0x0),
            "79d3d _ref neither valid nor 0x"
        );

        // Element must not exist to be added
        EntryLink storage element_values = _list._values[_element];
        if (element_values.prev == address(0x0)) {
            if (_list._last == address(0x0)) {
                // If the list is empty, set the element as both first and last
                element_values.prev = _element;
                element_values.next = _element;
                _list._first = _element;
                _list._last = _element;
            } else {
                if (_before && (_reference == address(0x0) || _reference == _list._first)) {
                    // Adding the element as the first element
                    address first = _list._first;
                    _list._values[first].prev = _element;
                    element_values.prev = _element;
                    element_values.next = first;
                    _list._first = _element;
                } else if (!_before && (_reference == address(0x0) || _reference == _list._last)) {
                    // Adding the element as the last element
                    address last = _list._last;
                    _list._values[last].next = _element;
                    element_values.prev = last;
                    element_values.next = _element;
                    _list._last = _element;
                } else {
                    // Inserting the element between two elements
                    EntryLink memory ref = _list._values[_reference];
                    if (_before) {
                        element_values.prev = ref.prev;
                        element_values.next = _reference;
                        _list._values[_reference].prev = _element;
                        _list._values[ref.prev].next = _element;
                    } else {
                        element_values.prev = _reference;
                        element_values.next = ref.next;
                        _list._values[_reference].next = _element;
                        _list._values[ref.next].prev = _element;
                    }
                }
            }
            _list._size = _list._size + 1;
            return true;
        }
        return false;
    }

    /**
     * @dev Removes an element from the linked list.
     * @param _list The storage pointer to the linked list.
     * @param _element The element to be removed.
     * @return A boolean indicating the success of the removal.
     */
    function remove(List storage _list, address _element) internal returns (bool) {
        EntryLink memory element_values = _list._values[_element];
        if (element_values.next != address(0x0)) {
            if (_element == _list._last && _element == _list._first) {
                // Removing the last and only element in the list
                delete _list._last;
                delete _list._first;
            } else if (_element == _list._first) {
                // Removing the first element
                address next = element_values.next;
                _list._values[next].prev = next;
                _list._first = next;
            } else if (_element == _list._last) {
                // Removing the last element
                address new_list_last = element_values.prev;
                _list._last = new_list_last;
                _list._values[new_list_last].next = new_list_last;
            } else {
                // Removing an element in between two other elements
                address next = element_values.next;
                address prev = element_values.prev;
                _list._values[next].prev = prev;
                _list._values[prev].next = next;
            }
            // Delete the element itself
            delete _list._values[_element];
            _list._size = _list._size - 1;
            return true;
        }
        return false;
    }
}
